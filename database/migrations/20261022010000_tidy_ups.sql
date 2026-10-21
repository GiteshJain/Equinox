-- Tidy-ups from the 21 Oct builds, and the cabin charge check (22 Oct 2026; spec docs/specs/2026-10-21-tidy-ups.md).
--
-- Why (Gitesh, 21 Oct: "finish the building"): the small things the scan-in-capture and competition builds turned up,
-- and the optional check from the cabins rule (manual §4: filing fits the plan card's cabin "and logs its first fit at
-- its price").
--
-- Adds and replaces (CREATE OR REPLACE, the same arguments); drops and renames nothing, so it can be applied from the
-- chat. Its only data changes: the new setting, unfinished scans marked stopped, and the registration and aircraft
-- filled on the game's cabin installation lines.
--   1. Scans that stop part-way:
--      - private.scan_progress(p_scan_id): how far a scan got (airlines and airports read), against the latest finished
--        scan of its world before it.
--      - private.scan_stop_unfinished(p_world_id, p_as_of): every unfinished scan (not done, not stopped) of the world
--        started more than an hour before p_as_of is marked stopped, with a note giving how far it got. Nothing could
--        carry it on: private.scan_open() looks back an hour.
--      - replaced: private.scan_ingest(), whose start (the capture's capture_scan() and gscan.py's ingest_snapshot())
--        marks them first; public.system_status(), which adds scan_stopped for the Systems board's scan line.
--      - the same for the unfinished scans there are when this runs (none on live on 21 Oct).
--      Every reader of game_scans already uses only finished scans (status done, or a scan with its airport summary,
--      which only finish builds): export_for_report()'s scan kinds (the scripts pick done ones), competition() and
--      private.competition_threats(), the fare ladder's rival pause and 60% floor, capture_scan_plan()'s scan_due, the
--      briefing (brief.py and competition()), hub_progress() and system_status(). The archive reads every scan by its
--      time, as it should. private.scan_open() reads unfinished ones on purpose, within the hour only.
--   2. The E190-E2 for thin 1-star cities (manual §3's default line: "3,542–4,065 km, or the thinnest 1-star city"):
--      replaced, private.fig_competition() (so competition() and the briefing): a 1-star opening whose variant is the
--      E195-E2 (the default small aircraft) also names the E190-E2 (variant_alt) with "or the E190-E2 if thin"
--      (variant_note). Nothing in our data says how thin a city is, so the evening proposal decides.
--   3. The cabin charge check:
--      - settings.cabin_charge_check_from, '2026-10-18', in every world, described.
--      - replaced: private.payment_registration() also reads "Installation of cabin interior (<reg>)"; new,
--        private.payment_aircraft(), the aircraft such a line names; replaced, private.fold_statement(), which fills
--        game_payments.aircraft_id with it. The lines already there get both.
--      - private.fig_cabin_charges(p_world_id, p_as_of) and the staff function public.cabin_charges(p_as_of), read with
--        GET: each first fit logged from the setting's day against the game's installation lines.
-- New private functions get no grants; cabin_charges() is for staff (signed in), as the other figures.

select set_config('equinox.actor', 'migration', true),
       set_config('equinox.actor_detail', '20261022010000_tidy_ups', true);

-- ============================================================ 1. scans that stop part-way
CREATE OR REPLACE FUNCTION private.scan_progress(p_scan_id bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  -- how far a world scan got: the airlines and airports it read, and the latest finished scan of its world before it
  -- with what that one read (what a whole scan reads), for "stopped after 812 of 1,040 airlines"
  with s as (select x.id, x.world_id, x.taken_at from public.game_scans x where x.id = p_scan_id),
  b as (select d.id, d.taken_at from public.game_scans d join s on d.world_id = s.world_id
         where d.status = 'done' and d.id <> s.id and d.taken_at <= s.taken_at
         order by d.taken_at desc, d.id desc limit 1)
  select jsonb_build_object(
           'airlines', (select count(*) from public.game_scan_airlines a where a.scan_id = s.id),
           'airports', (select count(*) from public.game_scan_airports a where a.scan_id = s.id),
           'before_id', b.id, 'before_at', private.fig_ts(b.taken_at),
           'airlines_expected', case when b.id is not null then (select count(*) from public.game_scan_airlines a where a.scan_id = b.id) end,
           'airports_expected', case when b.id is not null then (select count(*) from public.game_scan_airports a where a.scan_id = b.id) end)
    from s left join b on true
$function$;

CREATE OR REPLACE FUNCTION private.scan_stop_unfinished(p_world_id bigint, p_as_of timestamp with time zone)
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare r record; p jsonb; n int := 0;
begin
  -- a scan the capture started and never finished (the phone closed, the tab went away), more than an hour before: nothing
  -- carries it on any more (private.scan_open() looks back an hour), so it's stopped, and its note says how far it got
  for r in select s.id, s.note from public.game_scans s
            where s.world_id = p_world_id and s.status not in ('done', 'stopped') and s.taken_at <= p_as_of - interval '1 hour'
            order by s.taken_at, s.id
              for update loop
    p := private.scan_progress(r.id);
    update public.game_scans
       set status = 'stopped',
           note = format('stopped part-way after %s%s airlines and %s%s airports (marked %s UTC)',
                         p ->> 'airlines', coalesce(' of ' || (p ->> 'airlines_expected'), ''),
                         p ->> 'airports', coalesce(' of ' || (p ->> 'airports_expected'), ''),
                         to_char(p_as_of at time zone 'UTC', 'DD Mon HH24:MI'))
                  || coalesce(' · ' || nullif(r.note, ''), '')
     where id = r.id;
    n := n + 1;
  end loop;
  return n;
end
$function$;

CREATE OR REPLACE FUNCTION private.scan_ingest(p_world_id bigint, p_kind text, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare v_world bigint; v_scan bigint; v_al bigint; v_res jsonb; n int := 0;
begin
  if p_kind is null or p_kind not in ('start', 'airline', 'airport', 'finish', 'markets') then raise exception 'unknown kind'; end if;
  if p_kind = 'start' then
    if p_world_id is null then
      select x.id into v_world from public.worlds x where x.is_default;
    else
      v_world := p_world_id;
    end if;
    -- the world's scans left unfinished more than an hour ago are stopped first (spec docs/specs/2026-10-21-tidy-ups.md §1)
    perform private.scan_stop_unfinished(v_world, now());
    insert into public.game_scans (world_id, week, note) values (v_world, p_payload ->> 'week', p_payload ->> 'note')
    returning id into v_scan;
    v_res := jsonb_build_object('snapshot_id', v_scan);
  else
    select s.id, s.world_id into v_scan, v_world from public.game_scans s where s.id = (p_payload ->> 'snapshot_id')::bigint;
    if v_scan is null and p_kind <> 'finish' then
      raise exception 'no such scan: %', coalesce(p_payload ->> 'snapshot_id', '(none)');
    end if;
    if p_kind = 'airline' then
      v_al := private.scan_airline(v_world, (p_payload ->> 'enterprise_id')::int, p_payload ->> 'name');
      insert into public.game_scan_airlines as x (scan_id, world_id, enterprise_id, airline_id, name, n_flights, n_weekly, n_airports, position)
      values (v_scan, v_world, (p_payload ->> 'enterprise_id')::int, v_al, p_payload ->> 'name',
              (p_payload ->> 'n_flights')::int, (p_payload ->> 'n_weekly')::int, (p_payload ->> 'n_airports')::int,
              (select coalesce(max(y.position), 0) + 1 from public.game_scan_airlines y where y.scan_id = v_scan))
      on conflict (scan_id, enterprise_id) do update set airline_id = excluded.airline_id, name = excluded.name,
        n_flights = excluded.n_flights, n_weekly = excluded.n_weekly, n_airports = excluded.n_airports;
      insert into public.game_scan_schedules as x (scan_id, world_id, airline_id, flights)
      values (v_scan, v_world, v_al, coalesce(p_payload -> 'flights', '[]'::jsonb))
      on conflict (scan_id, airline_id) do update set flights = excluded.flights;
      v_res := jsonb_build_object('ok', true);
    elsif p_kind = 'airport' then
      -- the airlines stationed there are airlines the scan saw too
      perform private.scan_airline(v_world, (st ->> 'enterprise_id')::int, st ->> 'name')
         from jsonb_array_elements(case when jsonb_typeof(p_payload -> 'stations') = 'array' then p_payload -> 'stations' else '[]'::jsonb end) st
        where (st ->> 'enterprise_id') ~ '^\d{1,9}$';
      insert into public.game_scan_airports as x (scan_id, world_id, airport_code, game_airport_id, info, stations, news, position)
      values (v_scan, v_world, p_payload ->> 'code', (p_payload ->> 'airport_id')::int, p_payload -> 'info',
              p_payload -> 'stations', p_payload -> 'news',
              (select coalesce(max(y.position), 0) + 1 from public.game_scan_airports y where y.scan_id = v_scan))
      on conflict (scan_id, airport_code) do update set game_airport_id = excluded.game_airport_id, info = excluded.info,
        stations = excluded.stations, news = excluded.news;
      v_res := jsonb_build_object('ok', true);
    elsif p_kind = 'finish' then
      if v_scan is not null then
        update public.game_scans set status = 'done', note = coalesce(p_payload ->> 'note', note) where id = v_scan;
        perform private.scan_summarise(v_scan);
      end if;
      v_res := jsonb_build_object('ok', true);
    elsif p_kind = 'markets' then
      if jsonb_typeof(p_payload -> 'markets') is distinct from 'array' then
        raise exception 'markets: the payload needs a list, markets: [{enterprise_id, market, weekly_departures, city_pairs}]';
      end if;
      perform private.scan_airline(v_world, x.game_id, null)
         from (select distinct (m ->> 'enterprise_id')::int as game_id from jsonb_array_elements(p_payload -> 'markets') m
                where (m ->> 'enterprise_id') ~ '^\d{1,9}$') x;
      delete from public.scan_airline_markets where scan_id = v_scan;
      insert into public.scan_airline_markets (scan_id, world_id, airline_id, market, weekly_departures, city_pairs)
      select v_scan, v_world, al.id, m ->> 'market', (m ->> 'weekly_departures')::int, (m ->> 'city_pairs')::int
        from jsonb_array_elements(p_payload -> 'markets') m
        join public.airlines al on al.world_id = v_world and al.game_id = (m ->> 'enterprise_id')::int
       where (m ->> 'enterprise_id') ~ '^\d{1,9}$' and coalesce(m ->> 'market', '') <> '';
      get diagnostics n = row_count;
      v_res := jsonb_build_object('ok', true, 'rows', n);
    end if;
  end if;
  return v_res;
end
$function$;

CREATE OR REPLACE FUNCTION public.system_status(p_world_id bigint DEFAULT NULL::bigint, p_as_of timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare w bigint; v_at timestamptz := coalesce(p_as_of, now()); v_month timestamptz; v_snap jsonb; v_job jsonb; v_fb timestamptz;
  v_backup jsonb; v_good jsonb; v_arch jsonb; v_clean jsonb; v_scan jsonb; v_stopped jsonb; v_db bigint; v_pdf bigint; v_site bigint;
begin
  if not private.caller_is_staff() then raise exception 'only planner staff can read the systems board' using errcode = '42501'; end if;
  w := private.fig_world(p_world_id);
  v_month := date_trunc('month', v_at at time zone 'UTC') at time zone 'UTC';

  -- the daily snapshot: the latest capture day in the daily history, and how it was taken
  select jsonb_build_object('day', x.day, 'source', x.source, 'complete', x.complete, 'taken_at', private.fig_ts(x.taken_at), 'airlines', x.airlines)
    into v_snap
    from (select ad.day, string_agg(distinct ad.source, ', ') as source, bool_and(ad.complete) as complete, max(ad.taken_at) as taken_at,
                 count(*)::int as airlines
            from public.airline_days ad
           where ad.world_id = w and ad.taken_at <= v_at
           group by ad.day order by ad.day desc limit 1) x;
  select jsonb_build_object('job', j.job, 'status', j.status, 'at', private.fig_ts(j.started_at), 'note', left(j.note, 300))
    into v_job
    from public.job_runs j
   where j.job in ('snapshot', 'snapshot_fallback') and (j.world_id = w or j.world_id is null) and j.started_at <= v_at and j.status <> 'running'
   order by j.started_at desc, j.id desc limit 1;
  select max(j.started_at) into v_fb from public.job_runs j
   where j.job = 'snapshot_fallback' and (j.world_id = w or j.world_id is null) and j.started_at <= v_at;

  -- the nightly backup: its latest run, and the latest good copy (a good run passed its restore check)
  select jsonb_build_object('ran_at', private.fig_ts(b.ran_at), 'ok', b.ok, 'kind', b.kind, 'note', left(b.note, 300))
    into v_backup
    from public.backup_runs b where coalesce(b.kind, '') <> 'test' and b.ran_at <= v_at order by b.ran_at desc, b.id desc limit 1;
  select jsonb_build_object('ran_at', private.fig_ts(b.ran_at), 'bytes', b.bytes, 'tables', b.tables, 'rows', b.rows, 'files', b.files,
                            'object_key', b.object_key)
    into v_good
    from public.backup_runs b where coalesce(b.kind, '') <> 'test' and b.ok and b.ran_at <= v_at order by b.ran_at desc, b.id desc limit 1;

  -- the monthly archive: its runs this month, its latest run, and any table and month whose latest run failed
  select jsonb_build_object(
           'last_at', private.fig_ts(max(j.started_at)),
           'month', (v_at at time zone 'UTC')::date - (extract(day from v_at at time zone 'UTC')::int - 1),
           'runs_this_month', count(*) filter (where j.started_at >= v_month),
           'ok_this_month', count(*) filter (where j.started_at >= v_month and j.status = 'ok'),
           'rows_this_month', coalesce(sum((j.details ->> 'rows')::bigint) filter (where j.started_at >= v_month and j.status = 'ok'), 0),
           'failed', coalesce((select jsonb_agg(jsonb_build_object('table', f.details ->> 'table', 'month', f.for_month, 'at', private.fig_ts(f.started_at),
                                                                   'note', left(f.note, 200)) order by f.started_at)
                                 from (select distinct on (x.details ->> 'table', x.for_month) x.*
                                         from public.job_runs x
                                        where x.job = 'archive' and x.started_at <= v_at and x.status <> 'running'
                                        order by x.details ->> 'table', x.for_month, x.started_at desc, x.id desc) f
                                where f.status = 'failed'), '[]'::jsonb))
    into v_arch
    from public.job_runs j where j.job = 'archive' and j.started_at <= v_at and j.status <> 'running';

  -- the clean-ups: the latest run
  select jsonb_build_object('at', private.fig_ts(j.started_at), 'status', j.status, 'note', left(j.note, 300))
    into v_clean
    from public.job_runs j
   where j.job = 'cleanup' and (j.world_id = w or j.world_id is null) and j.started_at <= v_at and j.status <> 'running'
   order by j.started_at desc, j.id desc limit 1;

  -- the world scan: the latest that has its airport summary (as hub_progress() reads it)
  select jsonb_build_object('taken_at', private.fig_ts(s.taken_at), 'week', s.week, 'status', s.status)
    into v_scan
    from public.game_scans s
   where s.world_id = w and s.taken_at <= v_at and exists (select 1 from public.scan_airline_airports x where x.scan_id = s.id)
   order by s.taken_at desc, s.id desc limit 1;
  -- a scan that stopped part-way since the latest finished one (spec docs/specs/2026-10-21-tidy-ups.md §1): marked stopped
  -- when the next scan started, or left unfinished for over an hour (nothing carries it on: private.scan_open())
  select jsonb_build_object('id', s.id, 'taken_at', private.fig_ts(s.taken_at), 'status', s.status, 'note', left(s.note, 300))
         || private.scan_progress(s.id)
    into v_stopped
    from public.game_scans s
   where s.world_id = w and s.taken_at <= v_at
     and (s.status = 'stopped' or (s.status not in ('done', 'stopped') and s.taken_at <= v_at - interval '1 hour'))
     and s.taken_at > coalesce((select max(d.taken_at) from public.game_scans d where d.world_id = w and d.status = 'done' and d.taken_at <= v_at),
                               '-infinity'::timestamptz)
   order by s.taken_at desc, s.id desc limit 1;

  -- usage the database can measure, each against its trigger (manual §1; #16, #17, #20): now, whatever the moment
  v_db := pg_database_size(current_database());
  select coalesce(sum(octet_length(r.pdf_b64)), 0) * 3 / 4 into v_pdf from public.site_reports r where r.pdf_b64 is not null;
  v_site := octet_length(public.site_public()::text);

  return jsonb_build_object(
    'world_id', w, 'as_of', private.fig_ts(v_at),
    'capture', private.fig_capture_status(w, v_at) -> 'airlines',
    'snapshot', coalesce(v_snap, '{}'::jsonb) || jsonb_build_object('last_run', v_job, 'fallback_at', private.fig_ts(v_fb)),
    'backup', jsonb_build_object('last', v_backup, 'last_good', v_good),
    'archive', v_arch,
    'cleanup', v_clean,
    'scan', v_scan,
    'scan_stopped', v_stopped,
    'usage', jsonb_build_array(
      jsonb_build_object('key', 'database', 'label', 'Database size', 'bytes', v_db, 'trigger_bytes', 350 * 1024 * 1024::bigint),
      jsonb_build_object('key', 'report_pdfs', 'label', 'Report PDFs', 'bytes', v_pdf, 'trigger_bytes', 50 * 1024 * 1024::bigint),
      jsonb_build_object('key', 'site_public', 'label', 'The website''s data', 'bytes', v_site, 'trigger_bytes', 500 * 1024::bigint)));
end
$function$;

-- the unfinished scans there are now, in every world (none on live on 21 Oct): ids, days and counts only
do $$
declare w record; n int := 0; v_list text;
begin
  for w in select x.id from public.worlds x order by x.id loop
    n := n + private.scan_stop_unfinished(w.id, now());
  end loop;
  select string_agg(format('scan %s of %s (%s)', s.id, to_char(s.taken_at at time zone 'UTC', 'DD Mon'), split_part(s.note, ' (marked', 1)), '; ' order by s.id)
    into v_list from public.game_scans s where s.status = 'stopped';
  raise notice 'scans marked stopped now: %; every stopped scan: %', n, coalesce(v_list, 'none');
end
$$;

-- ============================================================ 2. the E190-E2 for thin 1-star cities (openings)
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
      left join pfs o on o.scan_id = v_before and o.airline_id = pf.airline_id)
  select jsonb_build_object(
           'markets', (select d from markets), 'openings', (select d from openings),
           'openings_count', (select n from openings), 'openings_allowed', (select n_allowed from openings),
           'openings_left_out', (select n from left_out), 'openings_trunks', (select n_trunks from openings), 'profiles', (select d from profiles),
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
    'trunk_month', jsonb_build_object('on', v_trunks, 'from', v_trunk_from, 'to', v_trunk_to),
    'group', v_group,
    'markets', v_body -> 'markets',
    'threats', v_threats,
    'openings', v_body -> 'openings', 'openings_count', v_body -> 'openings_count', 'openings_allowed', v_body -> 'openings_allowed',
    'openings_left_out', v_body -> 'openings_left_out', 'openings_trunks', v_body -> 'openings_trunks',
    'profiles', v_body -> 'profiles',
    'pairs_flown', v_body -> 'pairs_flown', 'pairs_listed', v_body -> 'pairs_listed',
    'notes', jsonb_build_array(
      'Rivals are every airline in the scan that isn''t one of ours; departures a week count each flight''s days, as gscan.py counts them, passenger flights only (freighters left out, as the weekly report counts). Our own now are the airline''s live legs; before, its flights in the week-before scan.',
      'From trunk_month_from to trunk_month_to (November, manual §4) the trunks, pairs between two of our bases (any of our airlines''), come first, shortest first: hubs first isn''t applied to them and no distance leaves one out. Whether a trunk makes sense stays the Scheduling chat''s judgment.',
      'The variant is the default line''s (manual §3): the smallest size the city''s stars allow (1–2 stars small, 3 small or mid, 4 small to large, 5 mid or large), bigger only for reach, the cheapest per seat whose range with a full load covers the distance, among the types the airline may buy; beyond every narrowbody the A350 that is cheapest per seat, and beyond 15,000 km the one with the most seats. A 1-star opening whose variant is the default small aircraft (the E195-E2) also names the small type with the fewest seats (variant_alt, the E190-E2, "or the E190-E2 if thin" in variant_note): the default line gives it to the thinnest 1-star city, and nothing in our data says how thin a city is, so the evening proposal decides.'));
end
$function$;

-- ============================================================ 3. the cabin charge check
insert into public.settings (world_id, airline_id, key, value, unit, description, since, reason)
select w.id, null, 'cabin_charge_check_from', '"2026-10-18"'::jsonb, 'date',
       'The cabin charge check (cabin_charges(), Systems → Cabin charges and Today''s needs attention; manual §4) checks each first cabin fit logged from this day (UTC) on against the game''s installation line: the first day the plan card chose the cabin; earlier fits include refits',
       date '2026-10-21',
       'Gitesh, 21 Oct (spec docs/specs/2026-10-21-tidy-ups.md §3): every first fit logged since 18 Oct matched its game line to the dollar; the mismatches before it are refits, left alone'
  from public.worlds w
on conflict on constraint settings_world_airline_key_key do nothing;

CREATE OR REPLACE FUNCTION private.payment_registration(p_descr text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  -- "Leasing rate for B-0161" and the like; and the game's cabin installations, "Installation of cabin interior (9M-AAV)",
  -- since 22 Oct (spec docs/specs/2026-10-21-tidy-ups.md §3)
  select coalesce(
    substring(p_descr from '(?:for|of) ([A-Z0-9]{1,3}-[A-Z0-9]{2,6}|N[0-9]{1,5}[A-Z]{0,2})(?:$|[ ,.;(])'),
    case when p_descr ilike 'Installation of cabin interior%'
         then substring(p_descr from '\(([A-Z0-9]{1,3}-[A-Z0-9]{2,6}|N[0-9]{1,5}[A-Z]{0,2})\)') end)
$function$;

CREATE OR REPLACE FUNCTION private.payment_aircraft(p_world_id bigint, p_airline_id bigint, p_descr text)
 RETURNS bigint
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  -- the aircraft a cabin installation line names ("Installation of cabin interior (9M-AAV)"): the airline's own aircraft
  -- with that registration; null for every other line, as before (spec docs/specs/2026-10-21-tidy-ups.md §3)
  select ac.id from public.aircraft ac
   where p_descr ilike 'Installation of cabin interior%'
     and ac.world_id = p_world_id and ac.airline_id = p_airline_id and ac.registration = private.payment_registration(p_descr)
   order by ac.id
   limit 1
$function$;

CREATE OR REPLACE FUNCTION private.fold_statement(p_airline_id bigint, p_minutes timestamp with time zone[])
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare v_world bigint; v_n int;
begin
  if p_minutes is null or cardinality(p_minutes) = 0 then return 0; end if;
  select a.world_id into v_world from public.airlines a where a.id = p_airline_id;

  -- 1. these minutes' lines let go of their flights; they are tied again in 4
  update public.game_statement set flight_id = null
   where airline_id = p_airline_id and ts = any (p_minutes) and flight_id is not null;

  -- 2. money whose block is gone or changed: a money-only row goes; a flight already matched to its loads keeps them and
  --    loses the money, which 3 puts back as a money-only row to be matched again
  with b as materialized (select * from private.statement_blocks(p_airline_id, p_minutes) x where x.is_flight)
  delete from public.game_flights f
   where f.airline_id = p_airline_id and f.posted_at = any (p_minutes) and f.flight_no is null
     and not exists (select 1 from b where b.ts = f.posted_at and b.blk = f.statement_blk);
  with b as materialized (select * from private.statement_blocks(p_airline_id, p_minutes) x where x.is_flight)
  update public.game_flights f
     set posted_at = null, statement_blk = null, statement_routes = null, maint_registration = null, statement_pax = null,
         pax_income = null, cargo_income = null, fuel = null, onboard = null, handling = null, landing = null,
         atc = null, maintenance = null, income_total = null, cost_total = null, money_captured_at = null
   where f.airline_id = p_airline_id and f.posted_at = any (p_minutes) and f.flight_no is not null
     and not exists (select 1 from b where b.ts = f.posted_at and b.blk = f.statement_blk and b.routes_n = 1
                                       and b.route = f.origin_code || '-' || f.dest_code);

  -- 3. each flight block's money, by its minute and block; dep_at is the statement time until loads are matched
  insert into public.game_flights as f (world_id, airline_id, posted_at, statement_blk, statement_routes, origin_code,
         dest_code, dep_at, maint_registration, statement_pax, pax_income, cargo_income, fuel, onboard, handling,
         landing, atc, maintenance, income_total, cost_total, money_captured_at)
  select v_world, p_airline_id, b.ts, b.blk, b.routes_n, split_part(b.route, '-', 1), split_part(b.route, '-', 2), b.ts,
         b.tail, b.pax, b.pax_income, b.cargo_income, b.fuel, b.onboard, b.handling, b.landing, b.atc, b.maintenance,
         b.income_total, b.cost_total, b.captured_at
    from private.statement_blocks(p_airline_id, p_minutes) b
   where b.is_flight
  on conflict (airline_id, posted_at, statement_blk) where posted_at is not null do update set
    statement_routes = excluded.statement_routes,
    origin_code = case when f.flight_no is null then excluded.origin_code else f.origin_code end,
    dest_code = case when f.flight_no is null then excluded.dest_code else f.dest_code end,
    dep_at = case when f.flight_no is null then excluded.dep_at else f.dep_at end,
    maint_registration = excluded.maint_registration, statement_pax = excluded.statement_pax,
    pax_income = excluded.pax_income, cargo_income = excluded.cargo_income, fuel = excluded.fuel,
    onboard = excluded.onboard, handling = excluded.handling, landing = excluded.landing, atc = excluded.atc,
    maintenance = excluded.maintenance, income_total = excluded.income_total, cost_total = excluded.cost_total,
    money_captured_at = excluded.money_captured_at
  where (f.statement_routes, f.maint_registration, f.statement_pax, f.pax_income, f.cargo_income, f.fuel, f.onboard,
         f.handling, f.landing, f.atc, f.maintenance, f.income_total, f.cost_total, f.money_captured_at)
        is distinct from
        (excluded.statement_routes, excluded.maint_registration, excluded.statement_pax, excluded.pax_income,
         excluded.cargo_income, excluded.fuel, excluded.onboard, excluded.handling, excluded.landing, excluded.atc,
         excluded.maintenance, excluded.income_total, excluded.cost_total, excluded.money_captured_at)
     or (f.flight_no is null and (f.origin_code, f.dest_code, f.dep_at)
                                 is distinct from (excluded.origin_code, excluded.dest_code, excluded.dep_at));
  get diagnostics v_n = row_count;

  -- 4. each flight line points at its flight
  update public.game_statement s set flight_id = f.id
    from public.game_flights f
   where s.airline_id = p_airline_id and s.ts = any (p_minutes) and not private.is_payment_line(s.descr, s.blk)
     and f.airline_id = p_airline_id and f.posted_at = s.ts and f.statement_blk = s.blk;

  -- 5. every other line is a payment, one row per statement line; a cabin installation names its aircraft (since 22 Oct,
  --    spec docs/specs/2026-10-21-tidy-ups.md §3: the cabin charge check), and one found once stays
  insert into public.game_payments as p (world_id, airline_id, paid_at, kind, registration, aircraft_id, descr, amount, side,
         occ, statement_blk)
  select v_world, p_airline_id, s.ts, private.payment_kind(s.descr), private.payment_registration(s.descr),
         private.payment_aircraft(v_world, p_airline_id, s.descr), s.descr, s.amount, s.side, s.occ, s.blk
    from public.game_statement s
   where s.airline_id = p_airline_id and s.ts = any (p_minutes) and s.flight_id is null
  on conflict (airline_id, paid_at, descr, amount, occ) do update set
    kind = excluded.kind, registration = excluded.registration, aircraft_id = coalesce(excluded.aircraft_id, p.aircraft_id),
    side = excluded.side, statement_blk = excluded.statement_blk
  where (p.kind, p.registration, p.aircraft_id, p.side, p.statement_blk)
        is distinct from (excluded.kind, excluded.registration, coalesce(excluded.aircraft_id, p.aircraft_id), excluded.side,
                          excluded.statement_blk);
  delete from public.game_payments p
   where p.airline_id = p_airline_id and p.paid_at = any (p_minutes)
     and not exists (select 1 from public.game_statement s
                      where s.airline_id = p_airline_id and s.ts = p.paid_at and s.descr = p.descr
                        and s.amount = p.amount and s.occ = p.occ and s.flight_id is null);
  return v_n;
end
$function$;

-- the cabin installation lines already there get their registration and aircraft, as the fold now gives them
do $$
declare n int; n_reg int; n_ac int; n_inst int; n_train int; n_left int;
begin
  with x as (
    update public.game_payments p
       set registration = coalesce(p.registration, private.payment_registration(p.descr)),
           aircraft_id = coalesce(p.aircraft_id, private.payment_aircraft(p.world_id, p.airline_id, p.descr))
     where p.kind = 'cabin' and p.descr ilike 'Installation of cabin interior%'
       and (p.registration is distinct from coalesce(p.registration, private.payment_registration(p.descr))
            or p.aircraft_id is distinct from coalesce(p.aircraft_id, private.payment_aircraft(p.world_id, p.airline_id, p.descr)))
    returning p.registration, p.aircraft_id)
  select count(*), count(x.registration), count(x.aircraft_id) into n, n_reg, n_ac from x;
  select count(*) filter (where p.descr ilike 'Installation of cabin interior%'), count(*) filter (where p.descr ilike '%training%'),
         count(*) filter (where p.descr ilike 'Installation of cabin interior%' and (p.registration is null or p.aircraft_id is null))
    into n_inst, n_train, n_left from public.game_payments p where p.kind = 'cabin';
  raise notice 'cabin lines (kind cabin): % installations and % pilot training; % installation lines filled (% with a registration, % with an aircraft); % still without one or the other',
    n_inst, n_train, n, n_reg, n_ac, n_left;
end
$$;

CREATE OR REPLACE FUNCTION private.fig_cabin_charges(p_world_id bigint, p_as_of timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare
  w bigint := p_world_id;
  -- a fit with no charge yet is "not charged yet" once the airline's latest captured statement line is more than this
  -- after the day it was logged (spec docs/specs/2026-10-21-tidy-ups.md §3)
  v_wait constant interval := interval '2 days';
  v_from date; v_from_at timestamptz; v_doc jsonb;
begin
  select (s.value #>> '{}')::date into v_from from public.settings s
   where s.world_id = w and s.airline_id is null and s.key = 'cabin_charge_check_from';
  v_from_at := v_from::timestamp at time zone 'UTC';
  with
  al as (select * from private.fig_airlines(w)),
  -- each airline's latest captured statement line by the moment
  st as (select al.airline_id, x.ts as last_ts from al
           cross join lateral (select s.ts from public.game_statement s where s.airline_id = al.airline_id and s.captured_at <= p_as_of
                                order by s.ts desc limit 1) x),
  -- every first fit logged by the moment: spending_log kind cabin, "<reg> first cabin fit (<config>)", as Tails' filing
  -- logs it at the config's price
  fit as (select s.id, s.airline_id, s.aircraft_id, s.spent_on, s.amount, s.updated_at,
                 coalesce(substring(s.note from '^(\S+) first cabin fit'), ac.registration) as reg,
                 substring(s.note from 'first cabin fit \(([^)]*)\)') as config
            from public.spending_log s
            left join public.aircraft ac on ac.id = s.aircraft_id
           where s.world_id = w and s.airline_id in (select al.airline_id from al) and s.kind = 'cabin'
             and s.note ~ '^\S+ first cabin fit' and s.created_at <= p_as_of),
  -- the game's cabin installations from the setting's day: game_payments kind cabin, "Installation of cabin interior
  -- (<reg>)" (the pilot training an order brings, the same kind, left out), each as a cost (a credit counts against it)
  ln as (select p.id, p.airline_id, p.paid_at, p.descr, p.aircraft_id,
                case when p.side = 'C' then -p.amount else p.amount end as amount,
                coalesce(p.registration, private.payment_registration(p.descr)) as reg
           from public.game_payments p
          where p.world_id = w and p.airline_id in (select al.airline_id from al) and p.kind = 'cabin'
            and p.descr ilike 'Installation of cabin interior%' and p.paid_at >= v_from_at and p.created_at <= p_as_of),
  -- each first fit from the setting's day with the installation lines for its registration in its airline
  chk as (select f.*, st.last_ts,
                 (select count(*) from ln where ln.airline_id = f.airline_id and ln.reg = f.reg)::int as n,
                 (select ln.amount from ln where ln.airline_id = f.airline_id and ln.reg = f.reg order by ln.paid_at, ln.id limit 1) as game_amount,
                 (select coalesce(jsonb_agg(jsonb_build_object('id', ln.id, 'paid_at', private.fig_ts(ln.paid_at), 'amount', ln.amount, 'descr', ln.descr)
                                            order by ln.paid_at, ln.id), '[]'::jsonb)
                    from ln where ln.airline_id = f.airline_id and ln.reg = f.reg) as lines
            from fit f left join st on st.airline_id = f.airline_id
           where v_from is not null and f.spent_on >= v_from),
  ck as (select chk.*,
                case when chk.n > 1 then 'charged_twice'
                     when chk.n = 1 and abs(chk.game_amount - chk.amount) < 1 then 'matches'
                     when chk.n = 1 then 'differs'
                     when chk.last_ts > (chk.spent_on::timestamp at time zone 'UTC') + v_wait then 'not_charged'
                     else 'waiting' end as state
           from chk),
  -- installations for a registration with no first fit logged at all, on any day
  nl as (select ln.airline_id, ln.reg, min(ln.paid_at) as first_at, max(ln.aircraft_id) as aircraft_id,
                jsonb_agg(jsonb_build_object('id', ln.id, 'paid_at', private.fig_ts(ln.paid_at), 'amount', ln.amount, 'descr', ln.descr)
                          order by ln.paid_at, ln.id) as lines
           from ln
          where not exists (select 1 from fit f where f.airline_id = ln.airline_id and f.reg = ln.reg)
          group by ln.airline_id, ln.reg),
  pr as (select ck.airline_id, ck.state, ck.reg, ck.aircraft_id,
                jsonb_build_object('id', ck.id, 'spent_on', ck.spent_on, 'amount', ck.amount, 'config', ck.config,
                                   'updated_at', ck.updated_at) as logged,
                ck.lines, case when ck.n = 1 then ck.game_amount end as game_amount,
                case when ck.n = 1 then ck.game_amount - ck.amount end as difference,
                ck.spent_on::timestamp at time zone 'UTC' as at
           from ck where ck.state in ('differs', 'charged_twice', 'not_charged')
         union all
         select nl.airline_id, 'not_logged', nl.reg, nl.aircraft_id, null, nl.lines, null, null, nl.first_at
           from nl)
  select jsonb_build_object(
           'counts', jsonb_build_object(
             'checked', (select count(*) from ck),
             'matches', (select count(*) from ck where ck.state = 'matches'),
             'differs', (select count(*) from ck where ck.state = 'differs'),
             'charged_twice', (select count(*) from ck where ck.state = 'charged_twice'),
             'not_charged', (select count(*) from ck where ck.state = 'not_charged'),
             'waiting', (select count(*) from ck where ck.state = 'waiting'),
             'not_logged', (select count(*) from nl),
             'problems', (select count(*) from pr)),
           'problems', (select coalesce(jsonb_agg(jsonb_build_object(
                          'state', pr.state, 'airline_id', pr.airline_id, 'code', al.iata_code, 'airline', al.name,
                          'registration', pr.reg,
                          'aircraft_id', coalesce(pr.aircraft_id, (select ac.id from public.aircraft ac
                                                                    where ac.world_id = w and ac.airline_id = pr.airline_id and ac.registration = pr.reg
                                                                    order by ac.id limit 1)),
                          'logged', pr.logged, 'lines', pr.lines, 'game_amount', pr.game_amount, 'difference', pr.difference)
                          order by al.ord, case pr.state when 'differs' then 1 when 'charged_twice' then 2 when 'not_charged' then 3 else 4 end,
                                   pr.at, pr.reg), '[]'::jsonb)
                          from pr join al on al.airline_id = pr.airline_id),
           'latest_statement', (select coalesce(jsonb_object_agg(st.airline_id::text, private.fig_ts(st.last_ts)), '{}'::jsonb) from st))
    into v_doc;

  return jsonb_build_object(
    'world_id', w, 'as_of', private.fig_ts(p_as_of), 'check_from', v_from, 'wait_days', 2,
    'counts', v_doc -> 'counts', 'problems', v_doc -> 'problems', 'latest_statement', v_doc -> 'latest_statement',
    'notes', jsonb_build_array(
      case when v_from is null then 'The world has no cabin_charge_check_from setting: nothing is checked.'
           else format('First fits logged from %s on (cabin_charge_check_from: the first day the plan card chose the cabin; earlier fits include refits), each against the game''s installation lines for its registration from that day on.', v_from) end,
      'A fit matches with one line at its logged amount (to the dollar); differs with one line at another amount; is charged twice with more than one; is not charged yet with none once the airline''s latest captured statement line is more than 2 days after the day it was logged (waiting until then). An installation line for a registration with no first fit logged is not logged. Pilot training, the same kind on the statement, is left out.'));
end
$function$;

CREATE OR REPLACE FUNCTION public.cabin_charges(p_as_of timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if not private.caller_is_staff() then raise exception 'only planner staff can read the captured figures' using errcode = '42501'; end if;
  return private.fig_cabin_charges(private.fig_world(null), coalesce(p_as_of, now()));
end
$function$;

-- ============================================================ who may call them
revoke all on function private.scan_progress(bigint) from public, anon, authenticated, service_role;
revoke all on function private.scan_stop_unfinished(bigint, timestamptz) from public, anon, authenticated, service_role;
revoke all on function private.scan_ingest(bigint, text, jsonb) from public, anon, authenticated, service_role;
revoke all on function private.fig_competition(bigint, timestamptz, integer) from public, anon, authenticated, service_role;
revoke all on function private.payment_registration(text) from public, anon, authenticated, service_role;
revoke all on function private.payment_aircraft(bigint, bigint, text) from public, anon, authenticated, service_role;
revoke all on function private.fold_statement(bigint, timestamptz[]) from public, anon, authenticated, service_role;
revoke all on function private.fig_cabin_charges(bigint, timestamptz) from public, anon, authenticated, service_role;
revoke all on function public.cabin_charges(timestamptz) from public, anon, authenticated, service_role;
grant execute on function public.cabin_charges(timestamptz) to authenticated;

-- ============================================================ descriptions
comment on function private.scan_progress(bigint) is 'The world scan (spec docs/specs/2026-10-21-tidy-ups.md §1): how far a scan got, with no check of its own: airlines and airports, the rows it holds in game_scan_airlines and game_scan_airports; before_id and before_at, the latest finished scan of its world before it; airlines_expected and airports_expected, what that one read (null without one), so a stopped scan says "812 of 1,040 airlines". Read by private.scan_stop_unfinished() and system_status().';
comment on function private.scan_stop_unfinished(bigint, timestamptz) is 'The world scan (spec docs/specs/2026-10-21-tidy-ups.md §1): marks every unfinished scan of the world (status neither done nor stopped) started more than an hour before p_as_of as stopped, its note starting "stopped part-way after 812 of 1,040 airlines and 0 of 97 airports (marked 22 Oct 01:10 UTC)" (private.scan_progress(), against the latest finished scan before it), its old note kept after a dot. Nothing carries such a scan on (private.scan_open() looks back an hour), and the scans'' readers use finished scans only. Answers how many it marked. Called by private.scan_ingest()''s start and by migration 20261022010000.';
comment on function private.scan_ingest(bigint, text, jsonb) is 'The world scan''s writes (spec docs/specs/2026-10-21-scan-in-capture.md): ingest_snapshot()''s body, shared by ingest_snapshot() (scripts/scanner/gscan.py, the fallback) and capture_scan() (Capture all airlines), with no check of its own. Kinds: start (a game_scans row in p_world_id, the default world when null; answers snapshot_id; since 22 Oct it first marks the world''s scans left unfinished more than an hour ago as stopped, private.scan_stop_unfinished()), airline (its totals in game_scan_airlines and its schedule in game_scan_schedules, the airline placed in airlines by game ID through private.scan_airline()), airport (its page in game_scan_airports, the airlines stationed there placed too), finish (status done and the airport summaries, private.scan_summarise(); a scan that isn''t there is ignored) and markets (the weekly report''s market summaries, replacing the scan''s earlier ones). Every kind but start takes its scan''s own world. An unknown kind, or a scan that isn''t there, raises an error.';
comment on function public.system_status(bigint, timestamptz) is 'The Systems board at the top of the planner''s Systems screen (#23; Check''s until 20 Oct), read only, as of p_as_of (now by default) in a world (the default when null): capture, each airline''s latest page and verdicts (capture_status()''s airlines); snapshot, the latest day in airline_days with how it was taken (source capture, or fallback and so incomplete), the latest snapshot job and when the 10:00 UTC job last ran; backup, its latest run and latest good copy (restore check passed) with its size; archive, its runs this month, its latest run and any table and month whose latest run failed; cleanup, its latest run; scan, the latest world scan with its airport summary; scan_stopped (since 22 Oct, spec docs/specs/2026-10-21-tidy-ups.md §1), the latest scan after the latest finished one that stopped part-way (marked stopped, or left unfinished over an hour, which nothing carries on), with its id, taken_at, status, note and private.scan_progress() (airlines and airports read, and what the finished scan before it read), or null; usage, the database''s size, the report PDFs in site_reports (three quarters of their base64 text) and the size of site_public(), each with its trigger (manual §1: 350 MB, 50 MB, 500 KB), measured now. The board marks them. Staff only; runs as owner.';
comment on table public.game_scans is 'One row per world scan (design §3.9; was game_snapshots): when it ran, the week, its status and a note, with its world. Kept for good. Written by capture_scan() (Capture all airlines, when settings.scan_every_days says one is due; since 21 Oct) and by ingest_snapshot() (scripts/scanner/gscan.py, the fallback run by hand), both through private.scan_ingest(). Read by export_for_report() for the weekly report and gander monthly, and by the captured figures (competition(), fare_ladder(), hub_progress()), capture_airlines() and system_status(): only finished scans, but for a stopped one on the Systems board.';
comment on column public.game_scans.status is 'running (being read: the scanner or the capture is sending its pages), done (finished: the only scans the readers use) or stopped (since 22 Oct: left unfinished more than an hour, marked when the next scan starts, with a note of how far it got; private.scan_stop_unfinished())';
comment on function public.competition(bigint, timestamptz, integer) is 'Competition analysis for one airline (manual §3, market share first; spec docs/specs/2026-10-21-competition-analysis.md §1), as of p_as_of, from the world scans. scans: latest (the latest finished scan by then that still has its schedules), week_before (the latest at least 6 days older, else the oldest there is; null with one scan) and previous (the latest before latest), each with id and taken_at (UTC). group: our airlines'' passenger departures a week against the world''s (every airline''s schedule in the scan, freighters left out by private.scan_passenger(), the weekly report''s rule) and our share, now, in the week-before scan and the change. Freighters are no one''s rivals anywhere here: market share, threats, the openings'' rivals and the profiles count passenger flights only. markets: each of the airline''s markets (its routes not removed, flown or not, by market; No market for routes with none) with its city pairs (either direction) and how many it flies, ours (the airline''s live legs, both ways), ours_before (its flights in the week-before scan), every rival''s (every airline in the scan that isn''t one of ours) departures a week on the same pairs from the latest scan (rivals, rivals_before), our share (ours over ours and the rivals'', percent) and its change, and the top 5 rivals with their departures, change and share; biggest first. threats: private.competition_threats(), each with the rival, the route as the airline flies it, kind (started or added), then, added, now and ours, the scan''s day (on), until (7 days on), latest (shown by the latest scan) and words ("Air China started on PVG–CAN, 14 a week"). openings: each pair on the airline''s list (routes not removed; one route each, from the main hub first) that no airline of ours flies either way, with its stars, distance, the rivals flying it and their departures a week in the latest scan (both ways), the variant from the default line (manual §3: the smallest size the stars allow (1–2 small, 3 small or mid, 4 small to large, 5 mid or large; small up to 150 seats, mid 200, large 300, wide above), bigger only for reach (for_reach), the cheapest per seat whose range_km covers the distance, among the types the airline may buy (airline_aircraft_types); beyond every narrowbody the A350 cheapest per seat, beyond 15,000 km the one with the most seats; an opening no type reaches is left out and counted in openings_left_out), and hubs first (allowed, allowed_by and the reason when it isn''t: from the main hub always; from another base while the main hub is under hub_first_departures only if a rival has over contested_rival_weekly departures a week there (scan_airline_airports) or over contested_rival_daily a day from it to the destination; hub_first_exempt allows all). Ranked by stars, then rivals'' departures a week on the pair, then the shorter distance, then the route''s code, those hubs first doesn''t allow after the allowed ones; the top p_limit (50 by default; openings_count and openings_allowed count them all). From settings.trunk_month_from to trunk_month_to (1 to 30 November 2026, manual §4; trunk_month gives on, from and to): each trunk (a pair between two of our bases, any of our airlines'' hubs and focus cities in airline_bases) is marked trunk, allowed with allowed_by ''November trunk'' (hubs first suspended for trunks), never left out for reach (the world''s types when none the airline may buy reaches, variant.own false), and the trunks come first, shortest first, then the other openings as always (openings_trunks counts them); outside those days trunk is false and nothing changes. other_lists: our other airlines that have the pair on their own list (one airline per city pair, manual §2, decides). variant_alt and variant_note (since 22 Oct; spec docs/specs/2026-10-21-tidy-ups.md §2): on a 1-star opening whose variant is the default small aircraft (the E195-E2), the small type with the fewest seats the airline may buy that reaches it (the E190-E2), and the words "or the E190-E2 if thin": the default line gives the E190-E2 to the thinnest 1-star city, which nothing in our data measures, so the evening proposal decides; not there on any other opening. profiles: the 10 rivals who fly most of the airline''s city pairs (latest scan), each with its passenger departures a week (latest and week before), its airports and its 3 biggest by passenger departures, from its schedule, and the pairs shared with their departures and ours. hubs_first, settings and notes say what was used. Staff only; runs as owner and checks the caller itself. Read with GET.';
comment on function private.payment_registration(text) is 'The aircraft a payment names, e.g. B-0161 from "Leasing rate for B-0161", and since 22 Oct 9M-AAV from the game''s "Installation of cabin interior (9M-AAV)" (spec docs/specs/2026-10-21-tidy-ups.md §3). Null when it names none.';
comment on function private.payment_aircraft(bigint, bigint, text) is 'The cabin charge check (spec docs/specs/2026-10-21-tidy-ups.md §3): the aircraft a cabin installation line names ("Installation of cabin interior (9M-AAV)"), the airline''s own aircraft with that registration in the world (private.payment_registration()); null for any other line, or a registration the airline has no aircraft for. Read by private.fold_statement() for game_payments.aircraft_id.';
comment on function private.fold_statement(bigint, timestamp with time zone[]) is 'Folds an airline''s statement lines in the given minutes into game_flights (one row per flight block, matched by minute and block) and game_payments (every other line), and ties each flight line to its flight (game_statement.flight_id). Blocks that changed since are taken apart and folded again; a flight already matched keeps its loads. A payment names its aircraft''s registration (private.payment_registration()), and since 22 Oct a cabin installation line its aircraft too (private.payment_aircraft(); one found once stays). Run after every statement page, and by the backfill for every minute.';
comment on column public.game_payments.registration is 'The aircraft the line names, e.g. from "Leasing rate for B-0161", or since 22 Oct from the game''s "Installation of cabin interior (9M-AAV)"';
comment on column public.game_payments.aircraft_id is 'The aircraft: since 22 Oct, a cabin installation''s ("Installation of cabin interior (<reg>)"), the airline''s aircraft with that registration (private.payment_aircraft()), for the cabin charge check; empty on every other line';
comment on function private.fig_cabin_charges(bigint, timestamptz) is 'The captured figures (#19): builds cabin_charges()''s document with no check of its own. See cabin_charges().';
comment on function public.cabin_charges(timestamptz) is 'The cabin charge check (spec docs/specs/2026-10-21-tidy-ups.md §3; manual §4: filing fits the plan card''s cabin and logs its first fit at its price), in the default world, as of p_as_of (now by default), using only what was recorded by then: each first cabin fit logged from settings.cabin_charge_check_from on (2026-10-18, check_from: the first day the plan card chose the cabin; earlier fits include refits), from spending_log (kind cabin, note "<reg> first cabin fit (<config>)"), against the game''s installation lines for its registration in its airline from that day on (game_payments kind cabin, "Installation of cabin interior (<reg>)"; pilot training, the same kind, left out; a credit counts against). counts: checked, matches (one line at the logged amount, to the dollar: counted, not listed), differs (one line at another amount), charged_twice (more than one line), not_charged (no line, and the airline''s latest captured statement line more than 2 days after the day it was logged), waiting (no line yet, within those 2 days), not_logged (a registration with installation lines and no first fit logged on any day) and problems. problems: every one that isn''t a match or waiting, by airline (our order), then differs, charged twice, not charged yet and not logged, each with its state, airline_id, code, airline, registration, aircraft_id, logged (the spending_log row: id, spent_on, amount, config and updated_at, which a change to its amount is made from; null when not logged), lines (each game line: id, paid_at UTC, amount, descr), game_amount and difference (game less logged, AS$) where there is one line. latest_statement: each airline''s latest captured statement line. Today lists one item when there are problems, and Systems → Cabin charges lists them, with Use the game''s amount on a differing one. Staff only; runs as owner and checks the caller itself. Read with GET.';
comment on table public.spending_log is 'Money spent, in AS$: aircraft orders, cabins and refits, losses. Replaces the planner''s capex. Read by site_investor() and, since 22 Oct, cabin_charges() (each first cabin fit against the game''s charge; Systems → Cabin charges'' Use the game''s amount changes a fit''s amount through planner_save()).';

select set_config('equinox.actor', '', true), set_config('equinox.actor_detail', '', true);

-- The world scan in Capture all airlines (21 Oct 2026; spec docs/specs/2026-10-21-scan-in-capture.md §1; manual §7).
--
-- Why (Gitesh, 21 Oct; brief docs/briefs/2026-10-21-competition-analysis.md, outcome): competition analysis and the
-- evening order proposal need fresh rivals. Instead of Claude running scripts/scanner/gscan.py on Saturdays, the evening
-- capture (capture/capture_all.user.js, 1.5) scans the world itself when a scan is due, and sends what it reads with the
-- capture key. How often is a setting, scan_every_days, which starts at 1: every evening. gscan.py stays as the fallback,
-- run by hand, through ingest_snapshot() as before. Gander's owner allows the scanner (world_rules.world_scanner, §9).
--
-- Adds a setting and four functions and replaces two with the same arguments; changes, drops and renames nothing else,
-- so it can be applied from the chat:
--   - settings.scan_every_days, 1, in every world, described.
--   - private.scan_ingest(p_world_id, p_kind, p_payload): ingest_snapshot()'s body, moved here unchanged so the scanner
--     and the capture share it (start, airline, airport, finish and markets). p_world_id is the world a start scans (the
--     default world when null, as ingest_snapshot() always did); the other kinds take their scan's own world.
--   - public.ingest_snapshot(p_secret, p_kind, p_payload): its secret check, kinds, actor and answers unchanged; its body
--     now calls private.scan_ingest() with no world (the default world for a start).
--   - private.scan_open(p_world_id, p_as_of): an unfinished scan of the world started within the hour before p_as_of.
--   - private.capture_scan_plan(p_world_id, p_as_of): whether a scan is due (the latest finished scan at least
--     scan_every_days capture days old, or none), the open scan, and the airports to read: our bases, the big rival hubs
--     (gscan.py's list) and the latest finished scan's 20 busiest airports, without repeats.
--   - public.capture_airlines(p_key): as before, plus capture_scan_plan()'s answer for the key's world.
--   - public.capture_scan(p_key, p_kind, p_payload): with a valid capture key, start, airline, airport and finish as
--     ingest_snapshot() makes them, in the key's world. A bad key is refused as the capture refuses one. A start within
--     the hour of an unfinished scan of the same world carries on with that scan instead of starting another.

select set_config('equinox.actor', 'migration', true),
       set_config('equinox.actor_detail', '20261021233000_scan_in_capture', true);

-- ---------------------------------------------------------------- the setting
insert into public.settings (world_id, airline_id, key, value, unit, description, since, reason)
select w.id, null, 'scan_every_days', '1'::jsonb, 'days',
       'How often Capture all airlines also scans the world (capture/capture_all.user.js; manual §7): after our airlines, when the latest finished scan is at least this many capture days old (the 10:00-to-10:00 UTC day the capture uses), or there is none. 1 is every evening; 3 is about twice a week; 0 scans with every capture. Without this setting no scan is due. The Systems board marks the scan amber over 8 days and red over 15.',
       date '2026-10-21',
       'Gitesh, 21 Oct: every evening to start (brief docs/briefs/2026-10-21-competition-analysis.md); raise it to 3 if the evening gets long'
  from public.worlds w
on conflict on constraint settings_world_airline_key_key do nothing;

-- ---------------------------------------------------------------- ingest_snapshot()'s body, shared
create or replace function private.scan_ingest(p_world_id bigint, p_kind text, p_payload jsonb)
 returns jsonb
 language plpgsql
 set search_path to ''
as $function$
declare v_world bigint; v_scan bigint; v_al bigint; v_res jsonb; n int := 0;
begin
  if p_kind is null or p_kind not in ('start', 'airline', 'airport', 'finish', 'markets') then raise exception 'unknown kind'; end if;
  if p_kind = 'start' then
    if p_world_id is null then
      select x.id into v_world from public.worlds x where x.is_default;
    else
      v_world := p_world_id;
    end if;
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

create or replace function public.ingest_snapshot(p_secret text, p_kind text, p_payload jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_res jsonb;
  v_actor text := current_setting('equinox.actor', true); v_detail text := current_setting('equinox.actor_detail', true);
begin
  if not exists (select 1 from public.ingest_secret s where s.secret = p_secret) then raise exception 'not allowed'; end if;
  if p_kind is null or p_kind not in ('start', 'airline', 'airport', 'finish', 'markets') then raise exception 'unknown kind'; end if;
  perform set_config('equinox.actor', coalesce(nullif(v_actor, ''), 'script'), true),
          set_config('equinox.actor_detail', coalesce(nullif(v_detail, ''), 'ingest_snapshot'), true);
  -- the work is shared with the capture's scan (capture_scan()); a start scans the default world
  v_res := private.scan_ingest(null, p_kind, p_payload);
  perform set_config('equinox.actor', coalesce(v_actor, ''), true), set_config('equinox.actor_detail', coalesce(v_detail, ''), true);
  return v_res;
end
$function$;

-- ---------------------------------------------------------------- when to scan, and what
create or replace function private.scan_open(p_world_id bigint, p_as_of timestamp with time zone)
 returns bigint
 language sql
 stable
 set search_path to ''
as $function$
  select s.id from public.game_scans s
   where s.world_id = p_world_id and s.status <> 'done'
     and s.taken_at > p_as_of - interval '1 hour' and s.taken_at <= p_as_of
   order by s.taken_at desc, s.id desc
   limit 1
$function$;

create or replace function private.capture_scan_plan(p_world_id bigint, p_as_of timestamp with time zone)
 returns jsonb
 language plpgsql
 stable
 set search_path to ''
as $function$
declare
  -- the big rival hubs, with our hubs among them, as scripts/scanner/gscan.py lists them (its AP)
  c_hubs constant text[] := array['JFK', 'ORD', 'DFW', 'LAX', 'SFO', 'SEA', 'DEL', 'BOM', 'HYD', 'BLR', 'CCU', 'MAA', 'CDG',
    'AMS', 'BCN', 'MXP', 'MUC', 'LGW', 'MAN', 'EDI', 'PVG', 'PKX', 'SZX', 'KMG', 'XIY', 'KUL', 'LHR', 'SIN', 'DXB', 'DOH',
    'AUH', 'IST', 'HKG', 'ICN', 'BKK', 'PEK', 'CAN', 'CTU', 'HND', 'NRT', 'FRA', 'MAD', 'FCO', 'ATL', 'EWR', 'IAD', 'MIA',
    'YYZ', 'MEX', 'SYD', 'CGK', 'MNL', 'SGN', 'DUB', 'ZRH', 'VIE', 'CPH'];
  v_every int; v_latest bigint; v_latest_at timestamptz; v_due boolean; v_airports jsonb;
begin
  select (s.value #>> '{}')::numeric::int into v_every from public.settings s
   where s.world_id = p_world_id and s.airline_id is null and s.key = 'scan_every_days';
  -- the latest finished scan by the moment
  select s.id, s.taken_at into v_latest, v_latest_at from public.game_scans s
   where s.world_id = p_world_id and s.status = 'done' and s.taken_at <= p_as_of
   order by s.taken_at desc, s.id desc limit 1;
  -- due by capture day (the 10:00-to-10:00 UTC day the capture uses), so one evening is one day whichever side of
  -- midnight UTC it is captured; without the setting, never
  v_due := v_every is not null
           and (v_latest is null or private.capture_day(p_world_id, p_as_of) - private.capture_day(p_world_id, v_latest_at) >= v_every);
  -- the airports to read: our bases (our airlines in display order, each main hub first), the big rival hubs, then the
  -- latest finished scan's 20 busiest airports by departures a week; each once, where it first comes
  with ours as (
    select a.id, a.position from public.airlines a join public.groups g on g.id = a.group_id and g.world_id = a.world_id
     where a.world_id = p_world_id and a.active and g.kind = 'ours'),
  bases as (
    select b.airport_code as code, 1 as part,
           row_number() over (order by o.position nulls last, o.id, b.is_main desc, b.position nulls last, b.id) as k
      from public.airline_bases b join ours o on o.id = b.airline_id),
  hubs as (select h.code, 2 as part, h.k from unnest(c_hubs) with ordinality as h(code, k)),
  busiest as (
    select t.airport_code as code, 3 as part, row_number() over (order by t.weekly desc, t.airport_code) as k
      from (select x.airport_code, sum(x.weekly_departures) as weekly from public.scan_airline_airports x
             where x.scan_id = v_latest group by x.airport_code order by 2 desc, 1 limit 20) t),
  firsts as (
    select distinct on (e.code) e.code, e.part, e.k
      from (select * from bases union all select * from hubs union all select * from busiest) e
     where e.code ~ '^[A-Z0-9]{3}$'
     order by e.code, e.part, e.k)
  select coalesce(jsonb_agg(f.code order by f.part, f.k), '[]'::jsonb) into v_airports from firsts f;
  return jsonb_build_object(
    'scan_every_days', v_every,
    'scan_due', v_due,
    'scan_open', private.scan_open(p_world_id, p_as_of),
    'scan_latest', case when v_latest is not null then jsonb_build_object('id', v_latest, 'taken_at', private.fig_ts(v_latest_at)) end,
    'scan_airports', v_airports);
end
$function$;

create or replace function public.capture_airlines(p_key text)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
declare v_world bigint;
begin
  v_world := private.capture_key_world(p_key);
  if v_world is null then return jsonb_build_object('ok', false, 'error', 'bad key'); end if;
  return jsonb_build_object(
    'ok', true,
    'world', (select w.name from public.worlds w where w.id = v_world),
    'airlines', (select coalesce(jsonb_agg(jsonb_build_object('game_id', a.game_id, 'name', a.planner_name,
                                                               'game_name', a.game_name, 'code', a.iata_code)
                                           order by a.position nulls last, a.id), '[]'::jsonb)
                   from public.airlines a join public.groups g on g.id = a.group_id and g.world_id = a.world_id
                  where a.world_id = v_world and a.active and g.kind = 'ours'))
    -- the world scan (spec docs/specs/2026-10-21-scan-in-capture.md): whether one is due, the open one and the airports
    || private.capture_scan_plan(v_world, now());
end
$function$;

-- ---------------------------------------------------------------- the capture's scan
create or replace function public.capture_scan(p_key text, p_kind text, p_payload jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_world bigint; v_scan bigint; v_res jsonb;
  v_actor text := current_setting('equinox.actor', true); v_detail text := current_setting('equinox.actor_detail', true);
begin
  v_world := private.capture_key_world(p_key);
  if v_world is null then return jsonb_build_object('ok', false, 'error', 'bad key'); end if;
  if p_kind is null or p_kind not in ('start', 'airline', 'airport', 'finish') then
    return jsonb_build_object('ok', false, 'error', 'bad kind');
  end if;
  perform set_config('equinox.actor', coalesce(nullif(v_actor, ''), 'capture'), true),
          set_config('equinox.actor_detail', coalesce(nullif(v_detail, ''), 'capture_scan'), true);
  begin
    if p_kind = 'start' then
      -- one scan at a time: a capture run twice within the hour carries on with the scan it started
      perform pg_advisory_xact_lock(hashtext('equinox.capture_scan'), v_world::int);
      v_scan := private.scan_open(v_world, now());
      if v_scan is not null then
        v_res := jsonb_build_object('ok', true, 'snapshot_id', v_scan, 'carried_on', true);
      else
        v_res := private.scan_ingest(v_world, 'start', p_payload) || jsonb_build_object('ok', true, 'carried_on', false);
      end if;
    else
      -- only a scan of the key's world
      select s.id into v_scan from public.game_scans s
       where s.id = (p_payload ->> 'snapshot_id')::bigint and s.world_id = v_world;
      if v_scan is null then
        v_res := jsonb_build_object('ok', false, 'error', 'no such scan in this capture key''s world: ' || coalesce(p_payload ->> 'snapshot_id', '(none)'));
      else
        v_res := private.scan_ingest(v_world, p_kind, p_payload) || jsonb_build_object('snapshot_id', v_scan);
      end if;
    end if;
  exception when others then
    -- a payload that doesn't read is refused, writing nothing, and the scan carries on with the next page
    v_res := jsonb_build_object('ok', false, 'error', sqlerrm);
  end;
  perform set_config('equinox.actor', coalesce(v_actor, ''), true), set_config('equinox.actor_detail', coalesce(v_detail, ''), true);
  return v_res;
end
$function$;

-- ---------------------------------------------------------------- who may call them
revoke all on function private.scan_ingest(bigint, text, jsonb) from public, anon, authenticated, service_role;
revoke all on function private.scan_open(bigint, timestamptz) from public, anon, authenticated, service_role;
revoke all on function private.capture_scan_plan(bigint, timestamptz) from public, anon, authenticated, service_role;
revoke all on function public.capture_scan(text, text, jsonb) from public, anon, authenticated;
grant execute on function public.capture_scan(text, text, jsonb) to anon, authenticated;

-- ---------------------------------------------------------------- descriptions
comment on function private.scan_ingest(bigint, text, jsonb) is 'The world scan''s writes (spec docs/specs/2026-10-21-scan-in-capture.md): ingest_snapshot()''s body, shared by ingest_snapshot() (scripts/scanner/gscan.py, the fallback) and capture_scan() (Capture all airlines), with no check of its own. Kinds: start (a game_scans row in p_world_id, the default world when null; answers snapshot_id), airline (its totals in game_scan_airlines and its schedule in game_scan_schedules, the airline placed in airlines by game ID through private.scan_airline()), airport (its page in game_scan_airports, the airlines stationed there placed too), finish (status done and the airport summaries, private.scan_summarise(); a scan that isn''t there is ignored) and markets (the weekly report''s market summaries, replacing the scan''s earlier ones). Every kind but start takes its scan''s own world. An unknown kind, or a scan that isn''t there, raises an error.';
comment on function public.ingest_snapshot(text, text, jsonb) is 'Receives the world scanner''s results (start, airlines, airports, finish) into game_scans, game_scan_airlines, game_scan_schedules and game_scan_airports; finish builds the scan''s airport summaries. Kind markets takes the weekly report''s market summaries for a scan (scan_airline_markets). Every airline a scan sees gets an airlines row (change log actor script). Same kinds, payloads and answers as before #13; a start scans the default world. Since 21 Oct the work is private.scan_ingest(), which the evening capture''s scan (capture_scan()) shares; this stays for scripts/scanner/gscan.py, the fallback run by hand. Needs the ingest secret.';
comment on function private.scan_open(bigint, timestamptz) is 'The world scan (spec docs/specs/2026-10-21-scan-in-capture.md): the latest unfinished scan (status not done) of the world started in the hour up to p_as_of, or null. capture_scan() carries on with it instead of starting another; capture_airlines() gives it as scan_open.';
comment on function private.capture_scan_plan(bigint, timestamptz) is 'The world scan in Capture all airlines (spec docs/specs/2026-10-21-scan-in-capture.md; manual §7), for capture_airlines(), with no check of its own: scan_every_days (the setting; null when the world has none), scan_due (true when the world''s latest finished scan by p_as_of is at least scan_every_days capture days old, by private.capture_day(), or there is none; false without the setting), scan_open (private.scan_open()), scan_latest (that scan''s id and taken_at, UTC) and scan_airports, the airport codes the scan reads: our active airlines'' bases (in display order, each main hub first), the big rival hubs (scripts/scanner/gscan.py''s list) and the latest finished scan''s 20 busiest airports by departures a week (scan_airline_airports), each once, where it first comes.';
comment on function public.capture_airlines(text) is 'For the capture userscript, with the capture key: the key''s world and its active airlines of our groups (game ID, name, code), in display order, so the userscript doesn''t keep its own list. Since 21 Oct also the world scan (private.capture_scan_plan(), spec docs/specs/2026-10-21-scan-in-capture.md): scan_every_days, scan_due, scan_open, scan_latest and scan_airports, so the capture scans the world after our airlines when one is due. A wrong or missing key gets {"ok": false, "error": "bad key"}.';
comment on function public.capture_scan(text, text, jsonb) is 'The world scan in Capture all airlines (capture/capture_all.user.js 1.5; spec docs/specs/2026-10-21-scan-in-capture.md; manual §7), with the capture key: kinds start, airline, airport and finish, with the payloads scripts/scanner/gscan.py sends ingest_snapshot(), stored exactly as ingest_snapshot() stores them (private.scan_ingest()), in the key''s world. start answers {ok, snapshot_id, carried_on}: an unfinished scan of the world started within the hour (private.scan_open()) is carried on instead of starting another (one start at a time per world); the other kinds answer {ok, snapshot_id} and take only a scan of the key''s world. A wrong or missing key gets {"ok": false, "error": "bad key"}, an unknown kind {"ok": false, "error": "bad kind"}, and a payload that doesn''t read {"ok": false, "error": ...}, writing nothing. Every airline the scan sees gets an airlines row (change log actor capture, detail capture_scan). Runs as owner with an empty search path.';
comment on table public.game_scans is 'One row per world scan (design §3.9; was game_snapshots): when it ran, the week, its status and a note, with its world. Kept for good. Written by capture_scan() (Capture all airlines, when settings.scan_every_days says one is due; since 21 Oct) and by ingest_snapshot() (scripts/scanner/gscan.py, the fallback run by hand), both through private.scan_ingest(). Read by export_for_report() for the weekly report and gander monthly.';
comment on table public.game_scan_airlines is 'Each airline''s totals in a world scan (design §3.9; was game_snapshot_airlines): flights, weekly departures and airports, with its airlines row. Kept for good; the full schedule is in game_scan_schedules. Written by capture_scan() and ingest_snapshot() (private.scan_ingest()). Read by export_for_report().';
comment on table public.game_scan_airports is 'Each scanned airport''s page in a world scan (design §3.9; was game_snapshot_airports): its details, the airlines stationed there and its news. Kept one month, then archived (#13 pull request 7). Written by capture_scan() and ingest_snapshot() (private.scan_ingest()). Read by export_for_report().';
comment on table public.game_scan_schedules is 'Each airline''s full schedule in a world scan (design §3.9): one JSON list per airline, each flight as [code, number, from, to, weekdays, departure, arrival, aircraft type, operator]. Kept one month, then archived (#13 pull request 7). Written by capture_scan() and ingest_snapshot() (private.scan_ingest()). Read by export_for_report() and the airport summaries (private.scan_summarise).';
comment on table public.capture_keys is 'Hashed keys that let the in-game capture send data. Only hashes are stored. Each key belongs to one world (world_id): a page for an airline outside it is refused. Written by hand when a key is issued. Read by capture_ingest(), capture_airlines(), capture_fare_actions() and capture_scan().';

select set_config('equinox.actor', '', true), set_config('equinox.actor_detail', '', true);

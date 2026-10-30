-- The market pages, part 1: capture 1.9 and the database (30 Oct 2026; spec docs/specs/2026-10-30-market-pages.md; brief
-- docs/briefs/2026-10-29-market-pages.md, option C, decided 30 Oct).
--
-- Why (Gitesh, 30 Oct): the fare ladder moves on our own loads with no view of rivals' fares, and Competition's share is
-- estimated from the scan's departures. The game's Market Analysis page (/app/com/markets/<FROM><TO>) gives, for one
-- direction of one pair, every airline's flights with each class's price and seats left, the game's own passenger and
-- cargo share by calendar week, our service profile on the pair and the pair's weekly seats and price. Once a week, after
-- the evening's capture and its world scan, Capture all airlines (capture/capture_all.user.js 1.9) reads it for both
-- directions of every pair our airlines fly, parses it in the browser and sends only the figures here. Raw pages (about
-- 290 KB each) are never kept. Nothing reads the new tables yet except the tests and system_status(); the planner's
-- screens are part 2.
--
-- Adds a setting, five tables and six functions, and replaces seven functions with the same arguments; changes, drops and
-- renames nothing else, so it can be applied from the chat:
--   - settings.market_every_days, 7, in every world, described (0 switches the market pages off).
--   - public.market_runs: one row per run (open, done or stopped), with its pages read and failed. Kept for good.
--   - public.market_reads: one row per page a run read (our airline, origin, destination, ok or failed, the share's week,
--     our service profile on the pair). Detail: archived after a full calendar month.
--   - public.market_fares: per read, airline (by flight prefix) and class: flights seen, lowest, average and highest
--     price, flights finished and finished sold out. Nothing per flight. Detail: archived with its read.
--   - public.market_shares: per read, kind (passengers, cargo) and airline: the week, the share and its change in
--     points. Detail: archived with its read.
--   - public.market_weeks: per world, origin, destination and calendar week: seats offered and price per unit, the latest
--     read winning. Kept for good.
--   - private.market_open(), private.market_stop_unfinished(), private.capture_market_plan() and private.market_ingest():
--     the work, as the scan's is in private.scan_open(), private.scan_stop_unfinished(), private.capture_scan_plan() and
--     private.scan_ingest().
--   - public.capture_market(p_key, p_kind, p_payload): with the capture key, start, page and finish, in the key's world;
--     30 seconds at most a call, as export_for_report().
--   - public.capture_airlines(p_key): as before, plus capture_market_plan()'s answer (whether the market pages are due,
--     the open run and the pages to read, airline by airline).
--   - public.system_status(): as before, plus a market line (the latest finished run, its age, pages and failed).
--   - private.archive_tables(), archive_due(), archive_order(), archive_where() and archive_delete(): market_reads,
--     market_fares and market_shares go to the monthly archive by their read's time, one full calendar month kept, the
--     reads after their fares and shares (the delete refuses reads that fares or shares still point at).
-- All five tables: RLS on, one staff read rule, select for authenticated only, nothing for anon; only the functions
-- (as owner) write them.

select set_config('equinox.actor', 'migration', true),
       set_config('equinox.actor_detail', '20261030120000_market_pages', true);

-- ============================================================ 1. the setting
insert into public.settings (world_id, airline_id, key, value, unit, description, since, reason)
select w.id, null, 'market_every_days', '7'::jsonb, 'days',
       'How often Capture all airlines also reads the game''s Market Analysis pages (capture/capture_all.user.js 1.9; spec docs/specs/2026-10-30-market-pages.md): after the evening''s capture and its world scan, both directions of every pair our airlines fly, when the latest finished market run is at least this many capture days old (the 10:00-to-10:00 UTC day the capture uses), or there is none. 7 is once a week; 1 would be every evening. 0 switches the market pages off, as does no setting. A run started within the hour and not finished is carried on.',
       date '2026-10-30',
       'Gitesh, 30 Oct: once a week when due (brief docs/briefs/2026-10-29-market-pages.md, option C); every evening (1) later is a data-only change'
  from public.worlds w
on conflict on constraint settings_world_airline_key_key do nothing;

-- ============================================================ 2. the tables
create table public.market_runs (
  id bigint generated always as identity primary key,
  world_id bigint not null references public.worlds (id),
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  status text not null default 'open' check (status in ('open', 'done', 'stopped')),
  pages_expected integer check (pages_expected >= 0),
  pages_read integer not null default 0 check (pages_read >= 0),
  pages_failed integer not null default 0 check (pages_failed >= 0),
  note text,
  capture_version text,
  constraint market_runs_id_world_key unique (id, world_id),
  constraint market_runs_finished check ((status = 'done') = (finished_at is not null))
);
create index market_runs_world_started_idx on public.market_runs (world_id, started_at desc);

create table public.market_reads (
  id bigint generated always as identity primary key,
  run_id bigint not null,
  world_id bigint not null,
  airline_id bigint not null,
  origin text not null check (origin ~ '^[A-Z0-9]{3}$'),
  dest text not null check (dest ~ '^[A-Z0-9]{3}$'),
  read_at timestamptz not null default clock_timestamp(),
  ok boolean not null,
  error text,
  share_week text check (share_week ~ '^\d{4}-\d{2}$'),
  service_code text,
  service_profile_game_id integer,
  constraint market_reads_two_ends check (origin <> dest),
  constraint market_reads_ok_or_error check (ok = (error is null)),
  constraint market_reads_id_world_key unique (id, world_id),
  constraint market_reads_run_pair_key unique (run_id, origin, dest),
  constraint market_reads_run_world_fkey foreign key (run_id, world_id) references public.market_runs (id, world_id),
  constraint market_reads_airline_fkey foreign key (airline_id, world_id) references public.airlines (id, world_id)
);
create index market_reads_run_world_idx on public.market_reads (run_id, world_id);
create index market_reads_airline_world_idx on public.market_reads (airline_id, world_id);
create index market_reads_world_pair_idx on public.market_reads (world_id, origin, dest, read_at desc);
create index market_reads_read_at_idx on public.market_reads (read_at);

create table public.market_fares (
  read_id bigint not null,
  world_id bigint not null,
  airline_code text not null check (airline_code ~ '^[A-Z0-9]{2,3}$'),
  service_class text not null check (service_class in ('Y', 'C', 'F', 'Cargo')),
  airline_id bigint,
  flights integer not null check (flights > 0),
  price_low numeric,
  price_avg numeric,
  price_high numeric,
  finished integer not null check (finished >= 0),
  sold_out integer not null check (sold_out >= 0),
  primary key (read_id, airline_code, service_class),
  constraint market_fares_counts check (sold_out <= finished and finished <= flights),
  constraint market_fares_prices check (price_low <= price_avg and price_avg <= price_high),
  constraint market_fares_read_world_fkey foreign key (read_id, world_id) references public.market_reads (id, world_id),
  constraint market_fares_airline_fkey foreign key (airline_id, world_id) references public.airlines (id, world_id)
);
create index market_fares_read_world_idx on public.market_fares (read_id, world_id);
create index market_fares_airline_world_idx on public.market_fares (airline_id, world_id);

create table public.market_shares (
  read_id bigint not null,
  world_id bigint not null,
  kind text not null check (kind in ('passengers', 'cargo')),
  airline_id bigint not null,
  week text not null check (week ~ '^\d{4}-\d{2}$'),
  share_pct numeric(6,2) not null check (share_pct between 0 and 100),
  change_pts numeric(7,2),
  primary key (read_id, kind, airline_id),
  constraint market_shares_read_world_fkey foreign key (read_id, world_id) references public.market_reads (id, world_id),
  constraint market_shares_airline_fkey foreign key (airline_id, world_id) references public.airlines (id, world_id)
);
create index market_shares_read_world_idx on public.market_shares (read_id, world_id);
create index market_shares_airline_world_idx on public.market_shares (airline_id, world_id);

create table public.market_weeks (
  world_id bigint not null references public.worlds (id),
  origin text not null check (origin ~ '^[A-Z0-9]{3}$'),
  dest text not null check (dest ~ '^[A-Z0-9]{3}$'),
  week text not null check (week ~ '^\d{4}-\d{2}$'),
  seats integer check (seats >= 0),
  price_per_unit numeric check (price_per_unit >= 0),
  run_id bigint not null,
  read_at timestamptz not null,
  primary key (world_id, origin, dest, week),
  constraint market_weeks_run_world_fkey foreign key (run_id, world_id) references public.market_runs (id, world_id)
);
create index market_weeks_run_world_idx on public.market_weeks (run_id, world_id);

alter table public.market_runs enable row level security;
alter table public.market_reads enable row level security;
alter table public.market_fares enable row level security;
alter table public.market_shares enable row level security;
alter table public.market_weeks enable row level security;
create policy "staff read" on public.market_runs for select to authenticated using ((select public.is_planner_user()));
create policy "staff read" on public.market_reads for select to authenticated using ((select public.is_planner_user()));
create policy "staff read" on public.market_fares for select to authenticated using ((select public.is_planner_user()));
create policy "staff read" on public.market_shares for select to authenticated using ((select public.is_planner_user()));
create policy "staff read" on public.market_weeks for select to authenticated using ((select public.is_planner_user()));
revoke all on table public.market_runs, public.market_reads, public.market_fares, public.market_shares, public.market_weeks
  from public, anon, authenticated;
grant select on table public.market_runs, public.market_reads, public.market_fares, public.market_shares, public.market_weeks
  to authenticated;

-- ============================================================ 3. when to read, and what
create or replace function private.market_open(p_world_id bigint, p_as_of timestamp with time zone)
 returns bigint
 language sql
 stable
 set search_path to ''
as $function$
  select r.id from public.market_runs r
   where r.world_id = p_world_id and r.status = 'open'
     and r.started_at > p_as_of - interval '1 hour' and r.started_at <= p_as_of
   order by r.started_at desc, r.id desc
   limit 1
$function$;

create or replace function private.market_stop_unfinished(p_world_id bigint, p_as_of timestamp with time zone)
 returns integer
 language plpgsql
 set search_path to ''
as $function$
declare n int;
begin
  -- a run the capture started and never finished, more than an hour before: nothing carries it on any more
  -- (private.market_open() looks back an hour), so it's stopped, and its note says how far it got
  update public.market_runs r
     set status = 'stopped',
         note = format('stopped part-way after %s%s pages, %s failed (marked %s UTC)',
                       r.pages_read + r.pages_failed, coalesce(' of ' || r.pages_expected, ''), r.pages_failed,
                       to_char(p_as_of at time zone 'UTC', 'DD Mon HH24:MI'))
                || coalesce(' · ' || nullif(r.note, ''), '')
   where r.world_id = p_world_id and r.status = 'open' and r.started_at <= p_as_of - interval '1 hour';
  get diagnostics n = row_count;
  return n;
end
$function$;

create or replace function private.capture_market_plan(p_world_id bigint, p_as_of timestamp with time zone)
 returns jsonb
 language plpgsql
 stable
 set search_path to ''
as $function$
declare v_every int; v_latest bigint; v_latest_at timestamptz; v_due boolean; v_open bigint; v_pages jsonb; v_total int; v_done int;
begin
  select (s.value #>> '{}')::numeric::int into v_every from public.settings s
   where s.world_id = p_world_id and s.airline_id is null and s.key = 'market_every_days';
  -- the latest finished run by the moment (by when it started, as the world scan goes by its taken_at)
  select r.id, r.started_at into v_latest, v_latest_at from public.market_runs r
   where r.world_id = p_world_id and r.status = 'done' and r.started_at <= p_as_of
   order by r.started_at desc, r.id desc limit 1;
  -- due by capture day, as the world scan; 0 or no setting: never
  v_due := coalesce(v_every, 0) > 0
           and (v_latest is null or private.capture_day(p_world_id, p_as_of) - private.capture_day(p_world_id, v_latest_at) >= v_every);
  v_open := private.market_open(p_world_id, p_as_of);
  -- the pages: for each of our active airlines (display order), both directions of each pair it flies (a route with
  -- rotations, not removed), the pair's way out first; a pair two of our airlines fly is read once, under the first
  with ours as (
    select a.id, a.game_id, a.iata_code, a.planner_name, a.game_name, a.position from public.airlines a
      join public.groups g on g.id = a.group_id and g.world_id = a.world_id
     where a.world_id = p_world_id and a.active and g.kind = 'ours' and a.game_id is not null),
  flown as (
    select distinct on (least(r.hub_code, r.dest_code), greatest(r.hub_code, r.dest_code))
           o.id as airline_id, o.position, r.hub_code as a, r.dest_code as b
      from public.routes r join ours o on o.id = r.airline_id
     where r.world_id = p_world_id and not r.removed and r.hub_code ~ '^[A-Z0-9]{3}$' and r.dest_code ~ '^[A-Z0-9]{3}$'
       and r.hub_code <> r.dest_code
       and exists (select 1 from public.rotations x where x.route_id = r.id)
     order by least(r.hub_code, r.dest_code), greatest(r.hub_code, r.dest_code), o.position nulls last, o.id, r.id),
  pages as (
    select f.airline_id, f.position, f.a as origin, f.b as dest, 1 as dir from flown f
    union all
    select f.airline_id, f.position, f.b, f.a, 2 from flown f),
  todo as (
    select p.* from pages p
     where v_open is null
        or not exists (select 1 from public.market_reads m where m.run_id = v_open and m.origin = p.origin and m.dest = p.dest))
  select (select count(*) from pages)::int, coalesce((
           select jsonb_agg(jsonb_build_object('game_id', o.game_id, 'code', o.iata_code, 'name', o.planner_name, 'game_name', o.game_name,
                                               'pages', (select jsonb_agg(jsonb_build_array(t.origin, t.dest)
                                                                          order by least(t.origin, t.dest), greatest(t.origin, t.dest), t.dir)
                                                           from todo t where t.airline_id = o.id))
                            order by o.position nulls last, o.id)
             from ours o where exists (select 1 from todo t where t.airline_id = o.id)), '[]'::jsonb)
    into v_total, v_pages;
  v_done := case when v_open is null then 0 else (select count(*) from public.market_reads m where m.run_id = v_open)::int end;
  return jsonb_build_object(
    'market_every_days', v_every,
    'market_due', v_due,
    'market_open', v_open,
    'market_latest', case when v_latest is not null then jsonb_build_object('id', v_latest, 'started_at', private.fig_ts(v_latest_at),
                                                                            'finished_at', (select private.fig_ts(r.finished_at) from public.market_runs r where r.id = v_latest)) end,
    'market_total', v_total,
    'market_done', v_done,
    'market_pages', v_pages);
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
    || private.capture_scan_plan(v_world, now())
    -- the market pages (spec docs/specs/2026-10-30-market-pages.md): whether they're due, the open run and the pages
    || private.capture_market_plan(v_world, now());
end
$function$;

-- ============================================================ 4. the capture's market pages
create or replace function private.market_ingest(p_world_id bigint, p_kind text, p_payload jsonb)
 returns jsonb
 language plpgsql
 set search_path to ''
as $function$
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
            nullif(btrim(p_payload -> 'service' ->> 'code'), ''),
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
$function$;

create or replace function public.capture_market(p_key text, p_kind text, p_payload jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
 set statement_timeout to '30s'
as $function$
declare v_world bigint; v_run bigint; v_res jsonb;
  v_actor text := current_setting('equinox.actor', true); v_detail text := current_setting('equinox.actor_detail', true);
begin
  v_world := private.capture_key_world(p_key);
  if v_world is null then return jsonb_build_object('ok', false, 'error', 'bad key'); end if;
  if p_kind is null or p_kind not in ('start', 'page', 'finish') then
    return jsonb_build_object('ok', false, 'error', 'bad kind');
  end if;
  perform set_config('equinox.actor', coalesce(nullif(v_actor, ''), 'capture'), true),
          set_config('equinox.actor_detail', coalesce(nullif(v_detail, ''), 'capture_market'), true);
  begin
    if p_kind = 'start' then
      -- one run at a time: a capture run twice within the hour carries on with the run it started; one left open longer
      -- is stopped first
      perform pg_advisory_xact_lock(hashtext('equinox.capture_market'), v_world::int);
      perform private.market_stop_unfinished(v_world, now());
      v_run := private.market_open(v_world, now());
      if v_run is not null then
        v_res := jsonb_build_object('ok', true, 'run_id', v_run, 'carried_on', true);
      else
        v_res := private.market_ingest(v_world, 'start', coalesce(p_payload, '{}'::jsonb)) || jsonb_build_object('ok', true, 'carried_on', false);
      end if;
    else
      v_res := jsonb_build_object('ok', true) || private.market_ingest(v_world, p_kind, p_payload)
               || jsonb_build_object('run_id', (p_payload ->> 'run_id')::bigint);
    end if;
  exception when others then
    -- a payload that doesn't read is refused, writing nothing, and the run carries on with the next page
    v_res := jsonb_build_object('ok', false, 'error', sqlerrm);
  end;
  perform set_config('equinox.actor', coalesce(v_actor, ''), true), set_config('equinox.actor_detail', coalesce(v_detail, ''), true);
  return v_res;
end
$function$;

-- ============================================================ 5. the Systems board's market line
CREATE OR REPLACE FUNCTION public.system_status(p_world_id bigint DEFAULT NULL::bigint, p_as_of timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare w bigint; v_at timestamptz := coalesce(p_as_of, now()); v_month timestamptz; v_snap jsonb; v_job jsonb; v_fb timestamptz;
  v_backup jsonb; v_good jsonb; v_arch jsonb; v_clean jsonb; v_scan jsonb; v_stopped jsonb; v_market jsonb; v_db bigint; v_pdf bigint; v_site bigint;
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
  -- since 23 Oct (spec docs/specs/2026-10-23-rival-fleets.md §5) with the overview pages it read and failed
  select jsonb_build_object('taken_at', private.fig_ts(s.taken_at), 'week', s.week, 'status', s.status,
                            'fleet_pages', (select count(*) from public.scan_airline_profile p where p.scan_id = s.id and p.read_ok)::int,
                            'fleet_failed', (select count(*) from public.scan_airline_profile p where p.scan_id = s.id and not p.read_ok)::int)
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

  -- the market pages (spec docs/specs/2026-10-30-market-pages.md): the latest finished run, its age, pages and failed
  select jsonb_build_object('id', r.id, 'started_at', private.fig_ts(r.started_at), 'finished_at', private.fig_ts(r.finished_at),
                            'age_days', round((extract(epoch from v_at - r.finished_at) / 86400)::numeric, 1),
                            'pages_read', r.pages_read, 'pages_failed', r.pages_failed, 'note', left(r.note, 300))
    into v_market
    from public.market_runs r
   where r.world_id = w and r.status = 'done' and r.started_at <= v_at
   order by r.started_at desc, r.id desc limit 1;

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
    'market', v_market,
    'usage', jsonb_build_array(
      jsonb_build_object('key', 'database', 'label', 'Database size', 'bytes', v_db, 'trigger_bytes', 350 * 1024 * 1024::bigint),
      jsonb_build_object('key', 'report_pdfs', 'label', 'Report PDFs', 'bytes', v_pdf, 'trigger_bytes', 50 * 1024 * 1024::bigint),
      jsonb_build_object('key', 'site_public', 'label', 'The website''s data', 'bytes', v_site, 'trigger_bytes', 500 * 1024::bigint)));
end
$function$;

-- ============================================================ 6. the archive: the reads, their fares and shares
CREATE OR REPLACE FUNCTION private.archive_tables()
 RETURNS TABLE(table_name text, month_of text, keep_months integer)
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select * from (values ('game_flights', 'dep_at (UTC); the game''s date where dep_at isn''t known', 1),
                        ('game_events', 'event_date', 1),
                        ('game_scan_schedules', 'the scan''s time (game_scans.taken_at, UTC)', 1),
                        ('game_scan_airports', 'the scan''s time (game_scans.taken_at, UTC)', 1),
                        ('scan_rival_connections', 'the scan''s time (game_scans.taken_at, UTC)', 1),
                        ('market_reads', 'read_at (UTC)', 1),
                        ('market_fares', 'its read''s time (market_reads.read_at, UTC)', 1),
                        ('market_shares', 'its read''s time (market_reads.read_at, UTC)', 1),
                        ('change_log', 'changed_at (UTC)', 12)) v(table_name, month_of, keep_months)
$function$;

CREATE OR REPLACE FUNCTION private.archive_due(p_as_of date DEFAULT NULL::date)
 RETURNS TABLE(table_name text, month date, rows bigint)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
 SET "TimeZone" TO 'UTC'
AS $function$
  with k as (
    select t.table_name, private.archive_kept_from(t.table_name, coalesce(p_as_of, (now() at time zone 'UTC')::date)) as kept_from
      from private.archive_tables() t)
  select x.table_name, x.month, x.rows from (
    select 'game_flights' as table_name, date_trunc('month', coalesce(f.dep_at at time zone 'UTC', f.game_date::timestamp))::date as month, count(*) as rows
      from public.game_flights f, k
     where k.table_name = 'game_flights' and coalesce(f.dep_at at time zone 'UTC', f.game_date::timestamp) < k.kept_from::timestamp
     group by 2
    union all
    select 'game_events', date_trunc('month', e.event_date)::date, count(*)
      from public.game_events e, k
     where k.table_name = 'game_events' and e.event_date < k.kept_from
     group by 2
    union all
    select 'game_scan_schedules', date_trunc('month', s.taken_at at time zone 'UTC')::date, count(*)
      from public.game_scan_schedules x join public.game_scans s on s.id = x.scan_id, k
     where k.table_name = 'game_scan_schedules' and s.taken_at < k.kept_from::timestamp at time zone 'UTC'
     group by 2
    union all
    select 'game_scan_airports', date_trunc('month', s.taken_at at time zone 'UTC')::date, count(*)
      from public.game_scan_airports x join public.game_scans s on s.id = x.scan_id, k
     where k.table_name = 'game_scan_airports' and s.taken_at < k.kept_from::timestamp at time zone 'UTC'
     group by 2
    union all
    select 'scan_rival_connections', date_trunc('month', s.taken_at at time zone 'UTC')::date, count(*)
      from public.scan_rival_connections x join public.game_scans s on s.id = x.scan_id, k
     where k.table_name = 'scan_rival_connections' and s.taken_at < k.kept_from::timestamp at time zone 'UTC'
     group by 2
    union all
    select 'market_reads', date_trunc('month', m.read_at at time zone 'UTC')::date, count(*)
      from public.market_reads m, k
     where k.table_name = 'market_reads' and m.read_at < k.kept_from::timestamp at time zone 'UTC'
     group by 2
    union all
    select 'market_fares', date_trunc('month', m.read_at at time zone 'UTC')::date, count(*)
      from public.market_fares x join public.market_reads m on m.id = x.read_id, k
     where k.table_name = 'market_fares' and m.read_at < k.kept_from::timestamp at time zone 'UTC'
     group by 2
    union all
    select 'market_shares', date_trunc('month', m.read_at at time zone 'UTC')::date, count(*)
      from public.market_shares x join public.market_reads m on m.id = x.read_id, k
     where k.table_name = 'market_shares' and m.read_at < k.kept_from::timestamp at time zone 'UTC'
     group by 2
    union all
    select 'change_log', date_trunc('month', c.changed_at at time zone 'UTC')::date, count(*)
      from public.change_log c, k
     where k.table_name = 'change_log' and c.changed_at < k.kept_from::timestamp at time zone 'UTC'
     group by 2) x
   -- within a month the market reads come after their fares and shares, which point at them
   order by x.month, x.table_name = 'market_reads', x.table_name
$function$;

CREATE OR REPLACE FUNCTION private.archive_order(p_table text, p_as text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare a text := quote_ident(p_as);
begin
  return case p_table
    when 'game_flights' then format('%1$s.id', a)
    when 'game_events' then format('%1$s.airline collate "C", %1$s.event_date, %1$s.event_time collate "C", %1$s.descr collate "C"', a)
    when 'game_scan_schedules' then format('%1$s.scan_id, %1$s.airline_id', a)
    when 'game_scan_airports' then format('%1$s.scan_id, %1$s.airport_code collate "C"', a)
    when 'scan_rival_connections' then format('%1$s.scan_id, %1$s.airline_id, %1$s.origin collate "C", %1$s.dest collate "C", %1$s.via collate "C"', a)
    when 'market_reads' then format('%1$s.id', a)
    when 'market_fares' then format('%1$s.read_id, %1$s.airline_code collate "C", %1$s.service_class collate "C"', a)
    when 'market_shares' then format('%1$s.read_id, %1$s.kind collate "C", %1$s.airline_id', a)
    when 'change_log' then format('%1$s.id', a)
  end;
end
$function$;

CREATE OR REPLACE FUNCTION private.archive_where(p_month date, p_table text, p_as text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare
  f text := quote_literal(to_char(p_month, 'YYYY-MM-DD') || ' 00:00:00+00') || '::timestamptz';
  t text := quote_literal(to_char((p_month + interval '1 month')::date, 'YYYY-MM-DD') || ' 00:00:00+00') || '::timestamptz';
  fd text := quote_literal(to_char(p_month, 'YYYY-MM-DD')) || '::date';
  td text := quote_literal(to_char((p_month + interval '1 month')::date, 'YYYY-MM-DD')) || '::date';
  a text := quote_ident(p_as);
begin
  perform private.archive_check_args(p_month, p_table);
  return case p_table
    when 'game_flights' then format('((%1$s.dep_at >= %2$s and %1$s.dep_at < %3$s) or (%1$s.dep_at is null and %1$s.game_date >= %4$s and %1$s.game_date < %5$s))', a, f, t, fd, td)
    when 'game_events' then format('(%1$s.event_date >= %2$s and %1$s.event_date < %3$s)', a, fd, td)
    when 'game_scan_schedules' then format('exists (select 1 from public.game_scans s where s.id = %1$s.scan_id and s.taken_at >= %2$s and s.taken_at < %3$s)', a, f, t)
    when 'game_scan_airports' then format('exists (select 1 from public.game_scans s where s.id = %1$s.scan_id and s.taken_at >= %2$s and s.taken_at < %3$s)', a, f, t)
    when 'scan_rival_connections' then format('exists (select 1 from public.game_scans s where s.id = %1$s.scan_id and s.taken_at >= %2$s and s.taken_at < %3$s)', a, f, t)
    when 'market_reads' then format('(%1$s.read_at >= %2$s and %1$s.read_at < %3$s)', a, f, t)
    when 'market_fares' then format('exists (select 1 from public.market_reads m where m.id = %1$s.read_id and m.read_at >= %2$s and m.read_at < %3$s)', a, f, t)
    when 'market_shares' then format('exists (select 1 from public.market_reads m where m.id = %1$s.read_id and m.read_at >= %2$s and m.read_at < %3$s)', a, f, t)
    when 'change_log' then format('(%1$s.changed_at >= %2$s and %1$s.changed_at < %3$s)', a, f, t)
  end;
end
$function$;

CREATE OR REPLACE FUNCTION private.archive_delete(p_month date, p_table text, p_expected_count bigint, p_checksum text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
 SET "TimeZone" TO 'UTC'
 SET "DateStyle" TO 'ISO, YMD'
 SET "IntervalStyle" TO 'postgres'
 SET extra_float_digits TO '1'
 SET bytea_output TO 'hex'
AS $function$
declare
  t0 timestamptz := clock_timestamp(); v_kept date; c record; v_reasons text[] := '{}'; n bigint; v_deleted bigint;
  v_sum text; v_version text; v_job bigint; v_label text;
begin
  perform private.archive_check_args(p_month, p_table);
  v_label := p_table || ' ' || to_char(p_month, 'YYYY-MM');
  execute format('lock table public.%I in share row exclusive mode', p_table);
  v_kept := private.archive_kept_from(p_table, (now() at time zone 'UTC')::date);
  if p_month >= v_kept then
    v_reasons := v_reasons || format('%s is inside the kept window (%s keeps %s, from %s on)', to_char(p_month, 'YYYY-MM'),
      p_table, case when p_table = 'change_log' then 'the last 12 full months' else 'one full calendar month' end, to_char(v_kept, 'YYYY-MM'));
  end if;
  select * into c from private.archive_checksum(p_month, p_table);
  if p_expected_count is distinct from c.rows then
    v_reasons := v_reasons || format('the count doesn''t match (%s expected, %s there now)', coalesce(p_expected_count::text, 'none'), c.rows);
  end if;
  if p_checksum is distinct from c.checksum then
    v_reasons := v_reasons || 'the checksum doesn''t match (the rows changed since the manifest)'::text;
  end if;
  if p_table = 'game_flights' then
    -- every flight of the month is in route_days, as many per route and day as game_flights has (history_flows's rule)
    execute format($q$
      with f as (
        select x.airline_id, x.origin_code, x.dest_code, coalesce((x.dep_at at time zone 'UTC')::date, x.game_date) as day, count(*) as n
          from public.game_flights x
         where %s and (x.flight_no is not null or x.pax_income is not null)
           and coalesce(x.origin_code, '') <> '' and coalesce(x.dest_code, '') <> ''
         group by 1, 2, 3, 4)
      select count(*) from f
        left join public.route_days r on r.airline_id = f.airline_id and r.origin_code = f.origin_code
                                     and r.dest_code = f.dest_code and r.day = f.day
       where r.flights is distinct from f.n::int$q$, private.archive_where(p_month, p_table, 'x')) into n;
    if n > 0 then
      v_reasons := v_reasons || format('%s route day(s) of the month aren''t in route_days as game_flights has them (run private.history_flows() for the month first)', n);
    end if;
    execute format('select count(*) from public.game_statement s join public.game_flights x on x.id = s.flight_id where %s',
                   private.archive_where(p_month, p_table, 'x')) into n;
    if n > 0 then
      v_reasons := v_reasons || format('%s statement line(s) still point at these flights (the statement clean-up removes them after 14 days once it is switched on)', n);
    end if;
  end if;
  if p_table = 'market_reads' then
    -- the reads go last: their fares and shares point at them, and are archived first
    execute format('select (select count(*) from public.market_fares f where f.read_id in (select x.id from public.market_reads x where %1$s))
                         + (select count(*) from public.market_shares s where s.read_id in (select x.id from public.market_reads x where %1$s))',
                   private.archive_where(p_month, p_table, 'x')) into n;
    if n > 0 then
      v_reasons := v_reasons || format('%s market_fares or market_shares row(s) still point at these reads (archive those tables'' month first)', n);
    end if;
  end if;
  if cardinality(v_reasons) > 0 then
    raise exception 'archive_delete refused %: %', v_label, array_to_string(v_reasons, '; ') using errcode = 'P0001';
  end if;

  -- the delete, checking the rows it removes against the manifest's count and checksum
  execute format('with d as (delete from public.%I t where %s returning t.*) select count(*), md5(coalesce(string_agg(d::text, E''\n'' order by %s), '''')) from d',
                 p_table, private.archive_where(p_month, p_table, 't'), private.archive_order(p_table, 'd'))
     into v_deleted, v_sum;
  if v_deleted <> p_expected_count or v_sum <> p_checksum then
    raise exception 'archive_delete stopped %: the rows it was deleting weren''t the manifest''s (% rows); nothing was deleted', v_label, v_deleted;
  end if;
  if to_regclass('supabase_migrations.schema_migrations') is not null then
    execute 'select max(version) from supabase_migrations.schema_migrations' into v_version;
  end if;
  insert into public.job_runs (job, started_at, finished_at, status, for_month, note, details)
  values ('archive', t0, clock_timestamp(), 'ok', p_month,
          format('%s: %s row(s) archived and deleted', v_label, v_deleted),
          jsonb_build_object('table', p_table, 'month', to_char(p_month, 'YYYY-MM'), 'rows', v_deleted, 'checksum', v_sum,
                             'migration_version', v_version))
  returning id into v_job;
  return jsonb_build_object('table', p_table, 'month', to_char(p_month, 'YYYY-MM'), 'deleted', v_deleted, 'job_run_id', v_job);
end
$function$;

-- ============================================================ 7. who may call them
revoke all on function private.market_open(bigint, timestamptz) from public, anon, authenticated, service_role;
revoke all on function private.market_stop_unfinished(bigint, timestamptz) from public, anon, authenticated, service_role;
revoke all on function private.capture_market_plan(bigint, timestamptz) from public, anon, authenticated, service_role;
revoke all on function private.market_ingest(bigint, text, jsonb) from public, anon, authenticated, service_role;
revoke all on function public.capture_market(text, text, jsonb) from public, anon, authenticated;
grant execute on function public.capture_market(text, text, jsonb) to anon, authenticated;

-- ============================================================ 8. descriptions
comment on table public.market_runs is 'One row per run of the market pages (since 30 Oct; spec docs/specs/2026-10-30-market-pages.md): Capture all airlines (capture/capture_all.user.js 1.9) reading the game''s Market Analysis page of both directions of every pair our airlines fly, once every settings.market_every_days capture days, after the evening''s capture and world scan. Status open (pages being sent), done (finished: the runs the readers use) or stopped (left open more than an hour, marked when the next run starts). Kept for good, as game_scans. Written only by capture_market() (private.market_ingest()); read by capture_airlines() (whether the pages are due) and system_status() (the Systems board''s market line). Staff read it.';
comment on column public.market_runs.id is 'The run''s own number, which the capture sends with each page and the finish';
comment on column public.market_runs.world_id is 'The world read (the capture key''s)';
comment on column public.market_runs.started_at is 'When the run started (its start call)';
comment on column public.market_runs.finished_at is 'When it was finished; null while open or once stopped';
comment on column public.market_runs.status is 'open (being read: the capture is sending its pages; one started within the hour is carried on), done (finished, with 10% or fewer of its pages failed) or stopped (left open more than an hour; marked by private.market_stop_unfinished() when the next run starts, with a note of how far it got)';
comment on column public.market_runs.pages_expected is 'The pages the capture meant to read when it started (both directions of every pair, capture_airlines()''s market_total); null when not sent';
comment on column public.market_runs.pages_read is 'Pages read and stored (market_reads ok), kept here when the reads are archived';
comment on column public.market_runs.pages_failed is 'Pages that didn''t read (market_reads not ok), kept here when the reads are archived';
comment on column public.market_runs.note is 'The capture''s note (its version, the pages and failed at the finish), or how far a stopped run got';
comment on column public.market_runs.capture_version is 'The capture userscript''s version that read it (1.9)';

comment on table public.market_reads is 'Each Market Analysis page a market run read (since 30 Oct; spec docs/specs/2026-10-30-market-pages.md): one direction of one pair, read with our airline that flies it open (the page''s prices and its service profile are that airline''s), ok or failed with the error, the week of its market shares and our service profile on the pair. The page itself is never kept (about 290 KB). Its figures are market_fares and market_shares; the pair''s weekly seats and price go to market_weeks. Detail: the monthly archive exports and deletes it after a full calendar month, after its fares and shares (private.archive_tables()). Written only by capture_market() (private.market_ingest()); a page sent again in the same run replaces the earlier one. Staff read it.';
comment on column public.market_reads.id is 'The read''s own number';
comment on column public.market_reads.run_id is 'The market run (market_runs)';
comment on column public.market_reads.world_id is 'The run''s world';
comment on column public.market_reads.airline_id is 'Our airline that flies the pair, open in the game when the page was read (airlines)';
comment on column public.market_reads.origin is 'The page''s origin airport, IATA (the first three letters of /app/com/markets/DUBAMS)';
comment on column public.market_reads.dest is 'The page''s destination airport, IATA';
comment on column public.market_reads.read_at is 'When the database stored the page; decides its month for the archive';
comment on column public.market_reads.ok is 'True when the page read; false when it didn''t, with the reason in error (no figures then)';
comment on column public.market_reads.error is 'Why the page didn''t read, as the capture sent it; null when it read';
comment on column public.market_reads.share_week is 'The calendar week the page''s Market Shares show, as 2026-44 (the page''s 44/2026)';
comment on column public.market_reads.service_code is 'Our service profile on the pair as the page''s settings form shows it selected (On-Board Service, e.g. R); null when none is selected. The pair''s setting: a per-flight-number setting the game may hold isn''t on this page. Read only; the form is never sent';
comment on column public.market_reads.service_profile_game_id is 'The game''s value of that service profile (318 for R on the saved page); null when none is selected';

comment on table public.market_fares is 'Each airline''s fares on a page the market pages read, by class (since 30 Oct; spec docs/specs/2026-10-30-market-pages.md): one row per read, flight prefix and class (Y, C, F, Cargo), over the flights the page''s Current Availability lists (finished yesterday, booked and in flight to about three days ahead): how many flights, the lowest, average and highest price in AS$, how many had finished and how many of those finished with no seat left (sold out; the page shows at most 9 seats left for a rival''s passengers, so it is not a load factor). The airline: airlines matched by the flight''s prefix where the latest finished world scan''s schedules give one airline that prefix, else an airline on the page''s share list with that IATA code, else none (airline_id null, the prefix kept). Nothing per flight is stored. Detail: the monthly archive exports and deletes it with its read after a full calendar month. Written only by capture_market() (private.market_ingest()). Staff read it.';
comment on column public.market_fares.read_id is 'The page it came from (market_reads)';
comment on column public.market_fares.world_id is 'The read''s world';
comment on column public.market_fares.airline_code is 'The flight number''s prefix as the page shows it (KL in KL 8)';
comment on column public.market_fares.service_class is 'The class as the page shows it: Y, C, F or Cargo';
comment on column public.market_fares.airline_id is 'The airline flying it (airlines), by the prefix as the table says; null when no airline could be told by it';
comment on column public.market_fares.flights is 'The flights with this prefix and class on the page';
comment on column public.market_fares.price_low is 'The lowest price among them, AS$';
comment on column public.market_fares.price_avg is 'The average price over them, AS$, to the cent';
comment on column public.market_fares.price_high is 'The highest price among them, AS$';
comment on column public.market_fares.finished is 'Of them, the flights already finished (status finished)';
comment on column public.market_fares.sold_out is 'Of the finished ones, those with 0 seats left in the class: sold out';

comment on table public.market_shares is 'Each airline''s share of a pair''s passengers and cargo, as a page the market pages read shows it (since 30 Oct; spec docs/specs/2026-10-30-market-pages.md): one row per read, kind (passengers, cargo) and airline, for the calendar week the page shows, with the change in points against the week before. The game''s own share, for one direction of the pair. The airline by the enterprise''s game id; one the database didn''t know gets an airlines row (change log actor capture), as the world scan does. Detail: the monthly archive exports and deletes it with its read after a full calendar month. Written only by capture_market() (private.market_ingest()). Staff read it.';
comment on column public.market_shares.read_id is 'The page it came from (market_reads)';
comment on column public.market_shares.world_id is 'The read''s world';
comment on column public.market_shares.kind is 'passengers or cargo (the page''s two tables)';
comment on column public.market_shares.airline_id is 'The airline (airlines), by the enterprise''s game id in the page''s link';
comment on column public.market_shares.week is 'The calendar week the share is for, as 2026-44';
comment on column public.market_shares.share_pct is 'Its share, % (68.46)';
comment on column public.market_shares.change_pts is 'The change against the week before, in points (−10.32); null when the page shows none';

comment on table public.market_weeks is 'A pair''s seats offered and price per unit by calendar week, as the market pages read them from each page''s Historic Capacities and Prices (since 30 Oct; spec docs/specs/2026-10-30-market-pages.md): one row per world, direction (origin to dest) and week with figures, the latest read winning (a week read again replaces its figures). For every airline on the pair together, as the game gives it. Kept for good: the archive leaves it alone. Written only by capture_market() (private.market_ingest()). Staff read it.';
comment on column public.market_weeks.world_id is 'The world';
comment on column public.market_weeks.origin is 'The direction''s origin airport, IATA';
comment on column public.market_weeks.dest is 'The direction''s destination airport, IATA';
comment on column public.market_weeks.week is 'The calendar week, as 2026-44 (the page''s period 202644); the current week is so far';
comment on column public.market_weeks.seats is 'Seats offered that week (the page''s capacities)';
comment on column public.market_weeks.price_per_unit is 'Price per unit that week, AS$ (the page''s prices)';
comment on column public.market_weeks.run_id is 'The market run whose read gave the figures (market_runs)';
comment on column public.market_weeks.read_at is 'When that page was read; a later read of the week wins';

comment on function private.market_open(bigint, timestamptz) is 'The market pages (spec docs/specs/2026-10-30-market-pages.md): the latest open market run of the world started in the hour up to p_as_of, or null. capture_market() carries on with it instead of starting another; capture_airlines() gives it as market_open.';
comment on function private.market_stop_unfinished(bigint, timestamptz) is 'The market pages (spec docs/specs/2026-10-30-market-pages.md): marks the world''s market runs left open more than an hour before p_as_of as stopped, with a note of how far each got ("stopped part-way after 120 of 686 pages, 2 failed (marked 30 Oct 21:40 UTC)"), as private.scan_stop_unfinished() does for scans; answers how many. Called by capture_market()''s start.';
comment on function private.capture_market_plan(bigint, timestamptz) is 'The market pages in Capture all airlines (spec docs/specs/2026-10-30-market-pages.md), for capture_airlines(), with no check of its own: market_every_days (the setting; null when the world has none), market_due (true when the setting is above 0 and the world''s latest finished market run started by p_as_of is at least that many capture days old by its start, by private.capture_day(), as the world scan''s, or there is none), market_open (private.market_open()), market_latest (that run''s id, started_at and finished_at, UTC), market_total (every page: both directions of every pair), market_done (pages the open run has read) and market_pages: for each of our active airlines in display order {game_id, code, name, game_name, pages}, pages being [origin, dest] for both directions of each pair it flies (a route with rotations, not removed), by pair, the way out first; a pair two of our airlines fly is listed once, under the first; the pages the open run has read left out, and airlines with none left out.';
comment on function private.market_ingest(bigint, text, jsonb) is 'The market pages'' writes (spec docs/specs/2026-10-30-market-pages.md), for capture_market(), with no check of its own. Kinds: start (a market_runs row in p_world_id, with the payload''s note, version and total; answers run_id), page (one Market Analysis page of an open run of the world: {run_id, airline (our airline''s game id), origin, dest, ok, error | week, previous_week, service {code, game_id}, fares [{code, cls, flights, low, avg, high, finished, sold_out}], shares [{kind, enterprise_id, name, share, change}], weeks [{week, seats, price}]}; replaces the run''s earlier read of the same page; writes market_reads, market_fares (the airline by prefix: the latest finished world scan''s schedules, else the share list''s airline with that IATA code), market_shares (unknown enterprises placed in airlines by private.scan_airline()) and market_weeks (weeks with figures, the latest read winning), and sets the run''s pages read and failed) and finish (status done; refused while more than 10% of the run''s pages failed). Raises an error for an unknown kind, a run that isn''t open in the world, an airline that isn''t ours, or figures that don''t read.';
comment on function public.capture_market(text, text, jsonb) is 'The market pages in Capture all airlines (capture/capture_all.user.js 1.9; spec docs/specs/2026-10-30-market-pages.md), with the capture key: kinds start, page and finish (private.market_ingest()), in the key''s world. start answers {ok, run_id, carried_on}: a run of the world left open more than an hour is marked stopped first (private.market_stop_unfinished()), and an open run started within the hour (private.market_open()) is carried on instead of starting another (one start at a time per world); page answers {ok, run_id, read_id, fares, shares, weeks, pages_read, pages_failed}; finish {ok, run_id, pages_read, pages_failed}, refused while more than 10% of the run''s pages failed. A wrong or missing key gets {"ok": false, "error": "bad key"}, an unknown kind {"ok": false, "error": "bad kind"}, and a payload that doesn''t read {"ok": false, "error": ...}, writing nothing. Never takes a page''s HTML: the capture sends only the figures. Every airline a page''s share list names gets an airlines row (change log actor capture, detail capture_market). Runs as owner with an empty search path, 30 seconds at most, as export_for_report().';
comment on function public.capture_airlines(text) is 'For the capture userscript, with the capture key: the key''s world and its active airlines of our groups (game ID, name, code), in display order, so the userscript doesn''t keep its own list. Since 21 Oct also the world scan (private.capture_scan_plan(), spec docs/specs/2026-10-21-scan-in-capture.md): scan_every_days, scan_due, scan_open, scan_latest and scan_airports, so the capture scans the world after our airlines when one is due. Since 30 Oct also the market pages (private.capture_market_plan(), spec docs/specs/2026-10-30-market-pages.md): market_every_days, market_due, market_open, market_latest, market_total, market_done and market_pages, airline by airline. A wrong or missing key gets {"ok": false, "error": "bad key"}.';
comment on function public.system_status(bigint, timestamptz) is 'The Systems board at the top of the planner''s Systems screen (#23; Check''s until 20 Oct), read only, as of p_as_of (now by default) in a world (the default when null): capture, each airline''s latest page and verdicts (capture_status()''s airlines); snapshot, the latest day in airline_days with how it was taken (source capture, or fallback and so incomplete), the latest snapshot job and when the 10:00 UTC job last ran; backup, its latest run and latest good copy (restore check passed) with its size; archive, its runs this month, its latest run and any table and month whose latest run failed; cleanup, its latest run; scan, the latest world scan with its airport summary (since 23 Oct with its overview pages read and failed); scan_stopped (since 22 Oct, spec docs/specs/2026-10-21-tidy-ups.md §1), the latest scan after the latest finished one that stopped part-way (marked stopped, or left unfinished over an hour, which nothing carries on), with its id, taken_at, status, note and private.scan_progress() (airlines and airports read, and what the finished scan before it read), or null; market (since 30 Oct, spec docs/specs/2026-10-30-market-pages.md), the latest finished market run started by p_as_of: its id, started_at, finished_at, age_days, pages_read, pages_failed and note, or null; usage, the database''s size, the report PDFs in site_reports (three quarters of their base64 text) and the size of site_public(), each with its trigger (manual §1: 350 MB, 50 MB, 500 KB), measured now. The board marks them. Staff only; runs as owner.';
comment on function private.archive_tables() is 'The tables the monthly archive may delete from (design §7), what decides a row''s month, and how many full calendar months each keeps: game_flights, game_events, game_scan_schedules, game_scan_airports, (since 23 Oct, spec docs/specs/2026-10-23-rival-connections.md §2) scan_rival_connections and (since 30 Oct, spec docs/specs/2026-10-30-market-pages.md) market_reads, market_fares and market_shares one; change_log 12.';
comment on function private.archive_where(date, text, text) is 'A table''s month as a condition on the table under an alias: one rule for the manifest, the export and the delete. game_flights by dep_at in UTC (by the game''s date where dep_at isn''t known, as the daily history counts it), game_events by event_date, the scan tables (game_scan_schedules, game_scan_airports and since 23 Oct scan_rival_connections) by their scan''s time, market_reads by read_at and (since 30 Oct) market_fares and market_shares by their read''s, change_log by changed_at.';
comment on function private.archive_order(text, text) is 'A table''s primary key as an order for the archive, text columns in byte order (collate "C"), so the order and the checksum are the same on any database.';
comment on function private.archive_due(date) is 'What the monthly archive has to do (design §7): each table''s months older than its kept window that still have rows, with their row counts, oldest first; within a month market_reads comes after the other tables (since 30 Oct: its fares and shares point at it, so they go first). Called by the archive step in equinox-backups every night (it runs on the first night on or after the 1st, and again each night until nothing is due). p_as_of: the day, default today in UTC (for the checks). postgres only.';
comment on function private.archive_delete(date, text, bigint, text) is 'The guarded delete (design §7), the only way the archive removes rows: refuses a table not listed, a month inside the kept window, a count or checksum that no longer matches, for game_flights a month whose flights aren''t all in route_days or that statement lines still point at, and (since 30 Oct) for market_reads a month whose reads market_fares or market_shares still point at, naming every reason in one refusal. Otherwise deletes exactly those rows (checked again as they go), records the run in job_runs (job archive, for_month) and answers with what it deleted and the row''s id. Locks the table against writes while it works. postgres only.';

select set_config('equinox.actor', '', true), set_config('equinox.actor_detail', '', true);

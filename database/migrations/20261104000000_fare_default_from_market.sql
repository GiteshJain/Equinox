-- The fare ladder reads the game's default price from the market pages (4 Nov 2026; spec
-- docs/specs/2026-11-04-fare-default-from-market.md, decided by Gitesh in the Scheduling chat: "on the market analysis
-- sheet, there is a market default rate and our highest current price for that route. we would still need to step back
-- incorrect fares as this would only tell us the highest one for that route" — "do it").
--
-- Why: the fare ladder never saw the game's default price. It took each direction's first captured fare to be at the
-- launch level (100%, Ryanair 85%) and read every later fare against it, so a direction first captured at another price
-- (a route opened mid-change, a new flight started elsewhere) had every level after it wrong, and the set-back check moved
-- its fares towards the wrong number (Ryanair's CDG–Hamburg on 4 Nov: first fare 118, today 100, read as "captured fare at
-- 72%, level 85%"; if 118 was the default, the fare is exactly at its 85%). The Market Analysis page's Pricing panel shows,
-- for each class, our current price (the highest of our flights that way) and the game's default price. Capture 1.11
-- reads it on every market page and sends it as pricing.
--
-- Adds one table and two functions, and replaces two functions with the same arguments; changes, drops and renames nothing
-- else, so it can be applied from the chat:
--   - public.market_prices: per market read and class (Y, C, F, Cargo), our airline's current and default price in AS$.
--     RLS on, one staff read rule, select for authenticated only, nothing for anon, as market_fares. Its read's foreign
--     key cascades: the monthly archive deletes market_reads after a full calendar month and doesn't list market_prices
--     (the archive's list is code in five functions, not data this change can extend safely; see the pull request), so a
--     read's prices go with it. Nothing reads prices that old: default_prices() needs the latest two runs.
--   - private.market_ingest(): as before, plus the page's pricing list (each class once, current and default above 0)
--     into market_prices; a page sent again replaces its prices; a page without pricing writes none. So capture_market()
--     answers a page with prices too.
--   - private.fig_default_prices(p_airline_id, p_as_of): for each of the airline's routes, direction and cabin (economy Y,
--     business C), the default and current price of the latest finished market run (finished by the moment) that read
--     that direction with the airline open, the run's date, and the default of the run before it.
--   - public.default_prices(p_airline_id, p_as_of default now()): the same as a document, staff only (signed in, checks
--     the caller itself, as owner with an empty search path). Small, so no statement limit of its own.
--   - private.fig_fare_ladder(): a direction's fare index (the captured level) is its latest captured day's fares ÷ the
--     default price × 100, rounded to 0.1, where the market pages have read it (default_source market, default_on the
--     run's date, baseline_fare the default price); elsewhere as before (default_source inferred). The set-back check is
--     unchanged in kind and measured the same way: any flight of the direction's latest captured day more than a point
--     off its level lists one change at its level. The levels, the moves, the cap, the floor and the jumps are unchanged.
--     inferred_index gives the old reading beside it, so the first run with prices can list the directions that were
--     priced against a wrong baseline (spec §4). fare_ladder() and capture_fare_actions_by_airline() read it, unchanged.

select set_config('equinox.actor', 'migration', true),
       set_config('equinox.actor_detail', '20261104000000_fare_default_from_market', true);

-- ============================================================ 1. the table
create table public.market_prices (
  read_id bigint not null,
  world_id bigint not null,
  airline_id bigint not null,
  service_class text not null check (service_class in ('Y', 'C', 'F', 'Cargo')),
  current_price numeric not null check (current_price > 0),
  default_price numeric not null check (default_price > 0),
  primary key (read_id, service_class),
  constraint market_prices_read_world_fkey foreign key (read_id, world_id) references public.market_reads (id, world_id) on delete cascade,
  constraint market_prices_airline_fkey foreign key (airline_id, world_id) references public.airlines (id, world_id)
);
create index market_prices_read_world_idx on public.market_prices (read_id, world_id);
create index market_prices_airline_world_idx on public.market_prices (airline_id, world_id);

alter table public.market_prices enable row level security;
create policy "staff read" on public.market_prices for select to authenticated using ((select public.is_planner_user()));
revoke all on table public.market_prices from public, anon, authenticated;
grant select on table public.market_prices to authenticated;

comment on table public.market_prices is 'Our airline''s current and default price on a page the market pages read, by class (since 4 Nov; spec docs/specs/2026-11-04-fare-default-from-market.md §2): one row per read and class (Y, C, F, Cargo), from the page''s Pricing panel, which belongs to the airline open when it was read (market_reads.airline_id). The default price is the game''s; the current price is the highest of our flights that way, so per-flight fares still come from the nightly capture. Capture 1.11 reads the panel only: the Pricing form is never sent. Read by default_prices() and the fare ladder (fare_ladder(): a direction''s level is measured against the default price where the market pages have one). Detail: its read''s foreign key cascades, so the monthly archive''s delete of a read takes its prices (market_prices isn''t on the archive''s list). Written only by capture_market() (private.market_ingest()); a page sent again in the same run replaces them. Staff read it.';
comment on column public.market_prices.read_id is 'The page it came from (market_reads)';
comment on column public.market_prices.world_id is 'The read''s world';
comment on column public.market_prices.airline_id is 'Our airline whose prices they are: the one open when the page was read (market_reads.airline_id)';
comment on column public.market_prices.service_class is 'The class as the Pricing panel shows it: Y (economy), C (business), F or Cargo';
comment on column public.market_prices.current_price is 'Current Price, AS$: what our airline charges that way, the highest of its flights';
comment on column public.market_prices.default_price is 'Default Price, AS$: the game''s default for the pair that way, the baseline Ticket price adjustment takes as 100%';

-- ============================================================ 2. the capture writes it
CREATE OR REPLACE FUNCTION private.market_ingest(p_world_id bigint, p_kind text, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  v_run record; v_al bigint; v_read bigint; v_origin text; v_dest text; v_scan bigint; v_at timestamptz;
  n_fares int := 0; n_shares int := 0; n_weeks int := 0; n_prices int := 0; v_bad text; v_read_n int; v_failed_n int;
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
    delete from public.market_prices where read_id = v_read;
    delete from public.market_reads where id = v_read;
  end if;

  if not (p_payload ->> 'ok')::boolean then
    insert into public.market_reads (run_id, world_id, airline_id, origin, dest, ok, error)
    values (v_run.id, p_world_id, v_al, v_origin, v_dest, false, coalesce(nullif(btrim(p_payload ->> 'error'), ''), 'no reason given'))
    returning id into v_read;
  else
    -- the lists, checked before anything is written
    if jsonb_typeof(coalesce(p_payload -> 'fares', '[]')) <> 'array' or jsonb_typeof(coalesce(p_payload -> 'shares', '[]')) <> 'array'
       or jsonb_typeof(coalesce(p_payload -> 'weeks', '[]')) <> 'array' or jsonb_typeof(coalesce(p_payload -> 'pricing', '[]')) <> 'array' then
      raise exception 'fares, shares, weeks and pricing must be lists';
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
    -- since 4 Nov (capture 1.11): the Pricing panel, each class once with its current and default price above 0
    select string_agg(coalesce(p ->> 'class', '?'), ', ') into v_bad
      from jsonb_array_elements(coalesce(p_payload -> 'pricing', '[]')) p
     where coalesce(p ->> 'class', '') not in ('Y', 'C', 'F', 'Cargo')
        or jsonb_typeof(p -> 'current') is distinct from 'number' or jsonb_typeof(p -> 'default') is distinct from 'number'
        or case when jsonb_typeof(p -> 'current') = 'number' then (p ->> 'current')::numeric end <= 0
        or case when jsonb_typeof(p -> 'default') = 'number' then (p ->> 'default')::numeric end <= 0;
    if v_bad is not null then raise exception 'pricing that doesn''t read: %', v_bad; end if;
    select string_agg(x.cls, ', ') into v_bad
      from (select p ->> 'class' as cls from jsonb_array_elements(coalesce(p_payload -> 'pricing', '[]')) p group by 1 having count(*) > 1) x;
    if v_bad is not null then raise exception 'pricing with a class twice: %', v_bad; end if;

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

    -- since 4 Nov (capture 1.11; spec docs/specs/2026-11-04-fare-default-from-market.md §2): our airline's current and
    -- default price for each class, from the page's Pricing panel (read only in the game)
    insert into public.market_prices (read_id, world_id, airline_id, service_class, current_price, default_price)
    select v_read, p_world_id, v_al, p ->> 'class', (p ->> 'current')::numeric, (p ->> 'default')::numeric
      from jsonb_array_elements(coalesce(p_payload -> 'pricing', '[]')) p;
    get diagnostics n_prices = row_count;

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
  return jsonb_build_object('read_id', v_read, 'fares', n_fares, 'shares', n_shares, 'weeks', n_weeks, 'prices', n_prices,
                            'pages_read', v_read_n, 'pages_failed', v_failed_n);
end
$function$

;


-- ============================================================ 3. the defaults, by route, direction and cabin
create or replace function private.fig_default_prices(p_airline_id bigint, p_as_of timestamp with time zone)
 returns table (route_id bigint, hub text, dest text, direction text, origin text, destination text, cabin text,
                default_price numeric, current_price numeric, run_id bigint, run_on date, read_at timestamptz,
                previous_default numeric, previous_run_on date)
 language sql
 stable
 set search_path to ''
as $function$
  with
  ro as (select r.id, r.hub_code, r.dest_code from public.routes r
          where r.airline_id = p_airline_id and r.world_id = (select a.world_id from public.airlines a where a.id = p_airline_id) and not r.removed),
  -- the airline's pages read ok in runs finished by the moment
  rd as (select m.id as read_id, m.origin, m.dest, m.read_at, r.id as run_id, r.started_at
           from public.market_reads m
           join public.market_runs r on r.id = m.run_id and r.world_id = m.world_id
          where m.airline_id = p_airline_id and m.ok and r.status = 'done' and r.finished_at <= p_as_of),
  -- each route, direction and cabin's prices, newest run first (economy Y, business C)
  px as (select ro.id as route_id, ro.hub_code as hub, ro.dest_code as dest,
                case when rd.origin = ro.hub_code then 'out' else 'back' end as direction, rd.origin, rd.dest as destination,
                case p.service_class when 'Y' then 'economy' else 'business' end as cabin,
                p.default_price, p.current_price, rd.run_id, (rd.started_at at time zone 'UTC')::date as run_on, rd.read_at,
                row_number() over (partition by ro.id, rd.origin, p.service_class order by rd.started_at desc, rd.run_id desc) as n
           from rd
           join public.market_prices p on p.read_id = rd.read_id and p.service_class in ('Y', 'C')
           join ro on (ro.hub_code = rd.origin and ro.dest_code = rd.dest) or (ro.hub_code = rd.dest and ro.dest_code = rd.origin))
  select c.route_id, c.hub, c.dest, c.direction, c.origin, c.destination, c.cabin, c.default_price, c.current_price, c.run_id, c.run_on,
         c.read_at, b.default_price, b.run_on
    from px c
    left join px b on b.route_id = c.route_id and b.origin = c.origin and b.cabin = c.cabin and b.n = 2
   where c.n = 1
$function$;

create or replace function public.default_prices(p_airline_id bigint, p_as_of timestamp with time zone default now())
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
begin
  if not private.caller_is_staff() then raise exception 'only planner staff can read the captured figures' using errcode = '42501'; end if;
  return jsonb_build_object(
    'airline_id', p_airline_id, 'as_of', private.fig_ts(coalesce(p_as_of, now())),
    'prices', (select coalesce(jsonb_agg(jsonb_build_object(
                 'route_id', d.route_id, 'hub', d.hub, 'dest', d.dest, 'direction', d.direction, 'from', d.origin, 'to', d.destination,
                 'cabin', d.cabin, 'default_price', d.default_price, 'current_price', d.current_price,
                 'current_pct', round(d.current_price / d.default_price * 100, 1),
                 'run_id', d.run_id, 'run_on', d.run_on, 'read_at', private.fig_ts(d.read_at),
                 'previous_default', d.previous_default, 'previous_run_on', d.previous_run_on,
                 'default_changed', d.previous_default is not null and d.previous_default <> d.default_price)
                 order by d.hub, d.dest, d.direction = 'back', d.cabin desc), '[]'::jsonb)
                 from private.fig_default_prices(p_airline_id, coalesce(p_as_of, now())) d));
end
$function$;

-- ============================================================ 4. the fare ladder measures against the default
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
  v_step numeric; v_up numeric; v_down numeric; v_min numeric; v_hold numeric; v_up_hold numeric; v_cap numeric; v_launch numeric; v_floor numeric;
  v_new_days numeric; v_added_days numeric;
  -- every route was at its launch level on 21 Oct 2026 (Gitesh; manual §5): each route's fare that day is its baseline
  v_base_day constant date := date '2026-10-21';
  v_scan bigint; v_scan_at timestamptz;
  v_rows jsonb; v_actions jsonb := '[]'::jsonb; v_n int := 0;
  v_r record; v_sets jsonb; v_change jsonb; v_lv numeric; v_words text;
  -- the fare ladder under launch (since 23 Oct; spec docs/specs/2026-10-23-fare-ladder-under-launch.md; judged by loads
  -- since 26 Oct, spec docs/specs/2026-10-26-under-launch-by-loads.md)
  v_ul_load numeric; v_ul_days numeric; v_ul_min numeric; v_ul_levels numeric[]; v_ul_below numeric[]; v_ul_j jsonb; v_ul_span text;
begin
  v_step := private.fig_num(w, p_airline_id, 'fare_ladder_step_pts');
  v_up := private.fig_num(w, p_airline_id, 'fare_ladder_up_share');
  v_down := private.fig_num(w, p_airline_id, 'fare_ladder_down_share');
  v_min := private.fig_num(w, p_airline_id, 'fare_ladder_min_departures');
  v_hold := private.fig_num(w, p_airline_id, 'fare_ladder_hold_weeks');
  -- the hold after a step up (since 26 Oct, manual §5): bookings open 3 days ahead (§9), so the week after a change mostly
  -- flies at the old price
  v_up_hold := private.fig_num(w, p_airline_id, 'fare_ladder_up_hold_weeks');
  v_cap := private.fig_num(w, p_airline_id, 'fare_ladder_cap_pts');
  v_launch := private.fig_num(w, p_airline_id, 'fare_launch_pct');
  v_new_days := private.fig_num(w, p_airline_id, 'growth_new_route_days');
  v_added_days := private.fig_num(w, p_airline_id, 'fare_ladder_capacity_hold_days');
  select (r.value #>> '{}')::numeric into v_floor from public.world_rules r where r.world_id = w and r.key = 'fare_floor_pct';
  -- under launch: a cabin at launch averaging under fare_under_launch_load_pct full over fare_under_launch_days jumps to
  -- the first of fare_under_launch_levels, holds that many days and is then judged on its loads like any direction (since
  -- 26 Oct; fare_under_launch_decide_load_pct is no longer read). An airline's own row wins over the world's, as fig_num()
  -- reads them
  v_ul_load := private.fig_num(w, p_airline_id, 'fare_under_launch_load_pct');
  v_ul_days := private.fig_num(w, p_airline_id, 'fare_under_launch_days');
  v_ul_min := private.fig_num(w, p_airline_id, 'fare_under_launch_min_flights');
  select s.value into v_ul_j from public.settings s
   where s.world_id = w and s.key = 'fare_under_launch_levels' and (s.airline_id is null or s.airline_id = p_airline_id)
   order by s.airline_id nulls last limit 1;
  if v_ul_j is null or jsonb_typeof(v_ul_j) <> 'array'
     or exists (select 1 from jsonb_array_elements(v_ul_j) e where jsonb_typeof(e) <> 'number') then
    raise exception 'setting fare_under_launch_levels is missing or isn''t a list of numbers' using errcode = '22023';
  end if;
  select array_agg((e #>> '{}')::numeric order by i) into v_ul_levels from jsonb_array_elements(v_ul_j) with ordinality as t(e, i);
  v_ul_span := case when v_ul_days > 0 and v_ul_days % 7 = 0
                    then format('%s week%s', trim_scale(v_ul_days / 7), case when v_ul_days = 7 then '' else 's' end)
                    else format('%s days', trim_scale(v_ul_days)) end;
  -- the jump levels under this airline's launch, in order (a level at or above launch is never a jump)
  select array_agg(u.l order by u.i) into v_ul_below from unnest(v_ul_levels) with ordinality as u(l, i) where u.l < v_launch;
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
  -- airline's list has it, either way round (as route profit matches them: route_id is often empty), and since 26 Oct its
  -- direction: out from the route's hub, back to it
  lf as materialized (
    select coalesce(r1.id, r2.id) as route_id, case when r1.id is not null then 'out' else 'back' end as dir, x.*
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
    select lf.route_id, 'economy'::text as cabin, lf.dir, lf.o, lf.game_date, lf.dep_at, lf.eco_pct as pct, lf.eco_fare as fare,
           coalesce(lf.dep_at, lf.game_date::timestamp at time zone 'UTC') as at from lf where lf.eco_pct is not null
    union all
    select lf.route_id, 'business', lf.dir, lf.o, lf.game_date, lf.dep_at, lf.bus_pct, lf.bus_fare,
           coalesce(lf.dep_at, lf.game_date::timestamp at time zone 'UTC') from lf where lf.bus_pct is not null and coalesce(lf.bus_seats, 0) > 0),
  -- the 7 days before the moment, by scheduled departure (the departure date where it isn't known), per direction since
  -- 26 Oct, with the direction's average load in the cabin
  st as (select lc.route_id, lc.cabin, lc.dir, count(*)::int as n, (count(*) filter (where lc.pct >= 100))::int as sold, avg(lc.fare) as fare,
                avg(lc.pct) as load
           from lc
          where lc.at >= p_as_of - interval '7 days' and lc.at < p_as_of
          group by lc.route_id, lc.cabin, lc.dir),
  -- the fare index's baseline (manual §5, since 21 Oct). Each captured day's fare by cabin and direction: the flights'
  -- lowest (one the game priced otherwise, as a new flight at the default price on a Ryanair route, sits above it), else
  -- the daily history's average fare in that cabin (route_days, kept for good once the flights are archived): economy's,
  -- and since 22 Oct business's, on a day with business passengers
  dd as (select lc.route_id, lc.cabin, lc.o, lc.game_date as day, min(lc.fare) as fare from lc where lc.fare > 0 group by 1, 2, 3, 4),
  hd as (select coalesce(r1.id, r2.id) as route_id, c.cabin, d.origin_code as o, d.day, avg(c.fare) as fare
           from public.route_days d
           left join ro r1 on r1.hub_code = d.origin_code and r1.dest_code = d.dest_code
           left join ro r2 on r2.hub_code = d.dest_code and r2.dest_code = d.origin_code
           cross join lateral (values ('economy'::text, case when d.eco_fare_avg > 0 then d.eco_fare_avg end),
                                      ('business'::text, case when d.bus_pax > 0 and d.bus_fare_avg > 0 then d.bus_fare_avg end)) c (cabin, fare)
          where d.airline_id = p_airline_id and c.fare is not null and d.day <= v_today and coalesce(r1.id, r2.id) is not null
          group by 1, 2, 3, 4),
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
  -- each direction's baseline (since 26 Oct a row each: out from the route's hub, back to it)
  bs as (select base.route_id, base.cabin, case when base.o = ro.hub_code then 'out' else 'back' end as dir, avg(base.fare) as fare, max(base.day) as day
           from base join ro on ro.id = base.route_id group by 1, 2, 3),
  -- since 4 Nov (spec docs/specs/2026-11-04-fare-default-from-market.md §3): the game's default price for each direction
  -- and cabin, from the latest finished market run that read it with our airline open (private.fig_default_prices():
  -- economy Y, business C). Where there is one, a direction's captured fares are measured against it (×100); elsewhere
  -- against the inferred baseline above, times the launch level, as before
  dp as materialized (select d.route_id, d.cabin, d.direction as dir, d.default_price, d.run_on
                        from private.fig_default_prices(p_airline_id, p_as_of) d),
  eb as (select coalesce(dp.route_id, bs.route_id) as route_id, coalesce(dp.cabin, bs.cabin) as cabin, coalesce(dp.dir, bs.dir) as dir,
                coalesce(dp.default_price, bs.fare) as fare,
                case when dp.default_price is not null then 100 else v_launch end as scale,
                case when dp.default_price is not null then 'market' else 'inferred' end as source,
                case when dp.default_price is not null then dp.run_on else bs.day end as day,
                dp.run_on as default_on
           from dp full join bs on bs.route_id = dp.route_id and bs.cabin = dp.cabin and bs.dir = dp.dir),
  -- the latest captured day by cabin and direction: its average fare, and each flight's fare as a % of the default price:
  -- against the direction's default where the market pages read it, else against its inferred baseline times the launch
  -- level (since 4 Nov); and, to compare, against the inferred baseline always (inf)
  lday as (select lc.route_id, lc.cabin, lc.dir, max(lc.game_date) as day from lc where lc.fare > 0 group by 1, 2, 3),
  latest as (select ld.route_id, ld.cabin, ld.dir, ld.day, avg(lc.fare) as fare,
                    array_agg(lc.fare / e.fare * e.scale order by lc.dep_at) filter (where e.fare > 0) as ratios,
                    array_agg(lc.fare / b.fare * v_launch order by lc.dep_at) filter (where b.fare > 0) as inf
               from lday ld
               join lc on lc.route_id = ld.route_id and lc.cabin = ld.cabin and lc.dir = ld.dir and lc.game_date = ld.day and lc.fare > 0
               left join eb e on e.route_id = lc.route_id and e.cabin = lc.cabin and e.dir = lc.dir
               left join bs b on b.route_id = lc.route_id and b.cabin = lc.cabin and b.dir = lc.dir
              group by ld.route_id, ld.cabin, ld.dir, ld.day),
  -- the levels the fare plan recorded (manual §5): before this Saturday, the latest is the level; since it, this week's move.
  -- Since 26 Oct per direction: a row with a direction counts for that direction, a both-directions row (direction null,
  -- every row written before then) for each of them, so a direction's level is its own latest row, or the latest
  -- both-directions row if that is later (proposed on, then id)
  rec as (select fp.id, fp.route_id, coalesce(fp.cabin_class, 'economy') as cabin, d.dir, fp.direction, fp.level_pct, fp.ladder_move,
                 fp.proposed_on, fp.reason, fp.fare_from, fp.change_pct
            from public.fare_plan fp
           cross join (values ('out'), ('back')) d (dir)
           where fp.airline_id = p_airline_id and fp.world_id = w and fp.level_pct is not null and fp.status <> 'dropped'
             and fp.proposed_on <= v_today and (fp.direction is null or fp.direction = d.dir)),
  prev as (select distinct on (r.route_id, r.cabin, r.dir) r.* from rec r where r.proposed_on < v_week
            order by r.route_id, r.cabin, r.dir, r.proposed_on desc, r.id desc),
  wk as (select distinct on (r.route_id, r.cabin, r.dir) r.* from rec r where r.proposed_on >= v_week
          order by r.route_id, r.cabin, r.dir, r.proposed_on desc, r.id desc),
  dn as (select r.route_id, r.cabin, r.dir, max(r.proposed_on) as down_on from rec r where r.ladder_move = 'down' and r.proposed_on < v_week group by 1, 2, 3),
  -- the latest step up before this Saturday (since 26 Oct, manual §5), a both-directions row counting for both as above.
  -- Only up: a jump and a set-back never start this hold (nor a revert, recorded before 26 Oct)
  upr as (select r.route_id, r.cabin, r.dir, max(r.proposed_on) as up_on from rec r where r.ladder_move = 'up' and r.proposed_on < v_week group by 1, 2, 3),
  -- under launch (since 23 Oct; spec docs/specs/2026-10-23-fare-ladder-under-launch.md §2), per direction since 26 Oct,
  -- judged by loads since 26 Oct (spec docs/specs/2026-10-26-under-launch-by-loads.md). Each cabin's day by day fare, each
  -- direction's and both directions' together (dir 'both', for a both-directions row), and its jumps recorded before this
  -- Saturday, each with the day it took effect: the first captured day on or after it was proposed whose fare (the row's
  -- direction's, or both directions' for a both-directions row) is the fare then times its ratio, within 1%
  -- (fare_plan_status()'s rule, read over every captured day, so the day holds once the flights are older than its 10
  -- days), else the day proposed
  cday as materialized (select lc.route_id, lc.cabin, coalesce(lc.dir, 'both') as dir, lc.game_date as day, avg(lc.fare) as fare
                          from lc where lc.fare > 0 group by grouping sets ((lc.route_id, lc.cabin, lc.dir, lc.game_date), (lc.route_id, lc.cabin, lc.game_date))),
  jr as (select r.id, r.route_id, r.cabin, r.dir, r.level_pct, r.proposed_on,
                coalesce((select min(c.day) from cday c
                           where c.route_id = r.route_id and c.cabin = r.cabin and c.dir = coalesce(r.direction, 'both') and c.day >= r.proposed_on and r.fare_from > 0
                             and abs(c.fare / r.fare_from - (1 + coalesce(r.change_pct, 0) / 100)) <= 0.01), r.proposed_on) as on_day
           from rec r where r.ladder_move = 'jump' and r.proposed_on < v_week),
  jl as (select distinct on (jr.route_id, jr.cabin, jr.dir) jr.route_id, jr.cabin, jr.dir, jr.id, jr.proposed_on, jr.on_day as jumped_on
           from jr order by jr.route_id, jr.cabin, jr.dir, jr.proposed_on desc, jr.id desc),
  -- done: a step recorded after the latest jump (it climbed: under launch the ladder then only climbs or holds, and never
  -- jumps again), or a revert recorded before 26 Oct (back at launch): no more jumps for that cabin and direction. A hold
  -- row doesn't end it (since 26 Oct)
  ud as (select jl.route_id, jl.cabin, jl.dir from jl
          where exists (select 1 from rec r where r.route_id = jl.route_id and r.cabin = jl.cabin and r.dir = jl.dir and r.proposed_on < v_week
                           and (r.ladder_move = 'revert' or (r.ladder_move in ('up', 'down') and (r.proposed_on, r.id) > (jl.proposed_on, jl.id))))),
  -- marked: a hold recorded after the latest jump (since 26 Oct the cut-or-keep mark, put on the fare plan the first
  -- Saturday a cabin at the last jump level is judged under fare_ladder_down_share sold out; before then the judgement
  -- that a jump paid): at the last level the cabin stays marked until it climbs
  um as (select jl.route_id, jl.cabin, jl.dir from jl
          where exists (select 1 from rec r where r.route_id = jl.route_id and r.cabin = jl.cabin and r.dir = jl.dir and r.proposed_on < v_week
                           and r.ladder_move = 'hold' and (r.proposed_on, r.id) > (jl.proposed_on, jl.id))),
  -- the latest recorded level change (any row but a hold): at launch, the window must be all at that level
  lch as (select r.route_id, r.cabin, r.dir, max(r.proposed_on) as changed_on from rec r where r.ladder_move is distinct from 'hold' group by 1, 2, 3),
  -- the window at launch: the fare_under_launch_days before the moment, by scheduled departure, the direction's flights
  uw as (select lc.route_id, lc.cabin, lc.dir, count(*)::int as n, avg(lc.pct) as load
           from lc where lc.at >= p_as_of - make_interval(days => v_ul_days::int) and lc.at < p_as_of group by 1, 2, 3),
  -- at the jump level: the direction's flights since the latest jump took effect, to the moment (shown, not judged on)
  uj as (select lc.route_id, lc.cabin, lc.dir, count(*)::int as n, avg(lc.pct) as load
           from lc join jl on jl.route_id = lc.route_id and jl.cabin = lc.cabin and jl.dir = lc.dir
          where lc.at >= jl.jumped_on::timestamp at time zone 'UTC' and lc.at < p_as_of
          group by 1, 2, 3),
  -- the window a cabin due at a jump level is judged on (since 2 Nov, manual §5): the fare_under_launch_days before the
  -- moment, none before the jump took effect; under fare_under_launch_load_pct full it may jump again
  ujw as (select lc.route_id, lc.cabin, lc.dir, count(*)::int as n, avg(lc.pct) as load
            from lc join jl on jl.route_id = lc.route_id and jl.cabin = lc.cabin and jl.dir = lc.dir
           where lc.at >= greatest(jl.jumped_on::timestamp at time zone 'UTC', p_as_of - make_interval(days => v_ul_days::int)) and lc.at < p_as_of
           group by 1, 2, 3),
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
  -- seats; any with flights captured in the 7 days or a move recorded this week. Since 26 Oct each in both directions
  rc as (select distinct x.route_id, x.cabin, d.dir
           from (select f.route_id, 'economy'::text as cabin from fq f where f.live
                 union all select bz.route_id, 'business' from biz bz
                 union all select st.route_id, st.cabin from st
                 union all select wk.route_id, wk.cabin from wk) x
           join ro on ro.id = x.route_id
           cross join (values ('out'), ('back')) d (dir)),
  lv as (select rc.route_id, rc.cabin, rc.dir, ro.hub_code as hub, ro.dest_code as dest,
                case rc.dir when 'out' then ro.hub_code else ro.dest_code end as dir_from,
                case rc.dir when 'out' then ro.dest_code else ro.hub_code end as dir_to,
                coalesce(st.n, 0) as n, coalesce(st.sold, 0) as sold, st.fare as fare_week, st.load as load_week,
                lt.fare as latest_fare, lt.day as latest_on, lt.ratios, lt.inf, eb.fare as baseline_fare, eb.day as baseline_on,
                coalesce(eb.source, 'inferred') as default_source, eb.default_on,
                coalesce(pv.level_pct, v_launch) as level, pv.id is not null as recorded,
                wk.id as plan_id, wk.level_pct as plan_level, wk.ladder_move as plan_move, wk.reason as plan_reason,
                coalesce(se.applied, false) as applied, se.seen_on, dn.down_on, upr.up_on, ag.first_day, ad.last_day,
                exists (select 1 from contested c where c.a = least(ro.hub_code, ro.dest_code) and c.b = greatest(ro.hub_code, ro.dest_code)) as contested,
                th.rival as rv_name, th.kind as rv_kind, th.added_weekly as rv_added, th.scan_at as rv_on, th.until as rv_until,
                jl.jumped_on, ud.route_id is not null as ul_done, um.route_id is not null as ul_marked, lch.changed_on,
                coalesce(uw.n, 0) as w_n, uw.load as w_load,
                coalesce(uj.n, 0) as j_n, uj.load as j_load,
                coalesce(ujw.n, 0) as jw_n, ujw.load as jw_load
           from rc join ro on ro.id = rc.route_id
           left join thr th on th.a = least(ro.hub_code, ro.dest_code) and th.b = greatest(ro.hub_code, ro.dest_code)
           left join st on st.route_id = rc.route_id and st.cabin = rc.cabin and st.dir = rc.dir
           left join latest lt on lt.route_id = rc.route_id and lt.cabin = rc.cabin and lt.dir = rc.dir
           left join eb on eb.route_id = rc.route_id and eb.cabin = rc.cabin and eb.dir = rc.dir
           left join prev pv on pv.route_id = rc.route_id and pv.cabin = rc.cabin and pv.dir = rc.dir
           left join wk on wk.route_id = rc.route_id and wk.cabin = rc.cabin and wk.dir = rc.dir
           left join seen se on se.id = wk.id
           left join dn on dn.route_id = rc.route_id and dn.cabin = rc.cabin and dn.dir = rc.dir
           left join upr on upr.route_id = rc.route_id and upr.cabin = rc.cabin and upr.dir = rc.dir
           left join age ag on ag.route_id = rc.route_id
           left join added ad on ad.route_id = rc.route_id
           left join jl on jl.route_id = rc.route_id and jl.cabin = rc.cabin and jl.dir = rc.dir
           left join ud on ud.route_id = rc.route_id and ud.cabin = rc.cabin and ud.dir = rc.dir
           left join um on um.route_id = rc.route_id and um.cabin = rc.cabin and um.dir = rc.dir
           left join lch on lch.route_id = rc.route_id and lch.cabin = rc.cabin and lch.dir = rc.dir
           left join uw on uw.route_id = rc.route_id and uw.cabin = rc.cabin and uw.dir = rc.dir
           left join uj on uj.route_id = rc.route_id and uj.cabin = rc.cabin and uj.dir = rc.dir
           left join ujw on ujw.route_id = rc.route_id and ujw.cabin = rc.cabin and ujw.dir = rc.dir),
  mv0 as (select lv.*,
                case when lv.n > 0 then lv.sold * 100.0 / lv.n end as share,
                v_launch + v_cap as cap_pct,
                -- never under launch, nor under the house floor where another player flies the pair
                greatest(v_launch, case when lv.contested then v_floor end) as floor_pct,
                coalesce(lv.first_day is not null and v_today - lv.first_day < v_new_days, false) as young,
                coalesce(lv.down_on is not null and v_week - lv.down_on < v_hold * 7, false) as held,
                -- the hold after a step up (since 26 Oct): the next Saturday, fare_ladder_up_hold_weeks
                coalesce(lv.up_on is not null and v_week - lv.up_on < v_up_hold * 7, false) as held_up,
                -- a flight added in the last fare_ladder_capacity_hold_days, to a route older than that (manual §5, since 21 Oct)
                coalesce(lv.last_day is not null and v_today - lv.last_day < v_added_days
                         and lv.first_day is not null and v_today - lv.first_day >= v_added_days, false) as added,
                -- under launch (since 23 Oct): the cabin's state, from the fare plan's rows before this Saturday. launch: at
                -- its launch level and never jumped; holding: its latest jump under fare_under_launch_days old, counted from
                -- the day it took effect; due: the hold is over, still at the jump level, judged on its loads each Saturday
                -- (since 26 Oct); done: it climbed after the jump, or is back at launch (a revert before 26 Oct)
                case when lv.jumped_on is null then case when lv.level = v_launch and v_ul_below is not null then 'launch' end
                     when lv.ul_done or lv.level >= v_launch then 'done'
                     when v_today - lv.jumped_on < v_ul_days then 'holding'
                     else 'due' end as ul_state,
                lv.jumped_on + v_ul_days::int as judge_on,
                -- the latest recorded level change (a cabin back at launch after a step down): the window must have none,
                -- so all its flights are at the launch level (spec §2); a new route waits as before (growth_new_route_days)
                lv.changed_on as launch_since,
                -- the jump levels under the cabin's level: the next is the first of them; at the last, none is left
                (select u.l from unnest(v_ul_below) with ordinality as u(l, i) where u.l < lv.level order by u.i limit 1) as next_level
           from lv),
  -- the under-launch kind (spec §2), worked out before this week's plan so a move put on the plan this week keeps it.
  -- Since 26 Oct (spec docs/specs/2026-10-26-under-launch-by-loads.md) a cabin due is judged on the week's loads as any
  -- direction: sold out it steps up and 90–99% sold out it holds (the normal ladder's own kinds); under 90% sold out, with
  -- the minimum departures, it jumps to the next level, or at the last level holds there marked cut or keep? Since 2 Nov
  -- (manual §5) the next jump also needs the cabin under fare_under_launch_load_pct full over its last fare_under_launch_days
  -- since the jump (ujw), as the first jump does; 80% full or more (or no flights in that window) it holds at its level
  -- (ul_full) and is judged again the next Saturday. The cut-or-keep test at the last level is unchanged.
  mv as (select mv0.*,
                case
                  when mv0.ul_state = 'launch' then
                    case when mv0.share >= v_down or mv0.n < v_min or mv0.w_load is null or mv0.w_load >= v_ul_load then null
                         when mv0.launch_since is not null and p_as_of - make_interval(days => v_ul_days::int) < mv0.launch_since::timestamp at time zone 'UTC' then 'ul_since'
                         when mv0.w_n < v_ul_min then 'ul_few'
                         else 'ul_jump' end
                  when mv0.ul_state = 'holding' then 'ul_hold'
                  when mv0.ul_state = 'due' then
                    case when mv0.n < v_min or mv0.share >= v_down then null
                         when mv0.next_level is not null and (mv0.jw_load is null or mv0.jw_load >= v_ul_load) then 'ul_full'
                         when mv0.next_level is not null then 'ul_jump'
                         else 'ul_decide' end
                end as uk
           from mv0),
  dc as (select mv.*,
                case when mv.plan_id is not null then 'planned'
                     when mv.young then 'young'
                     when mv.n < v_min then 'few'
                     -- a direction held both ways takes the more recent move's reason (the step down on the same day)
                     when mv.held and not (mv.held_up and mv.up_on > mv.down_on) then 'held'
                     when mv.held_up then 'held_up'
                     when mv.added then 'added'
                     when mv.rv_name is not null then 'rival'
                     -- under launch (since 23 Oct; spec §2): the jump at launch only where the ladder would hold at launch
                     -- (under fare_ladder_down_share sold out); the hold whatever it sells; once due (since 26 Oct) the next
                     -- jump or the cut-or-keep hold under fare_ladder_down_share sold out, else the normal ladder below
                     when mv.uk in ('ul_hold', 'ul_decide', 'ul_full') or (mv.uk = 'ul_jump' and mv.ul_state = 'due') then mv.uk
                     when mv.uk in ('ul_jump', 'ul_few', 'ul_since') and mv.level <= mv.floor_pct then mv.uk
                     -- under launch, once jumped, the ladder only climbs or holds (never a 5-point step down)
                     when mv.level < v_launch and mv.share < v_down then 'ul_climb'
                     when mv.share >= v_up then case when mv.level >= mv.cap_pct then 'capped' else 'up' end
                     when mv.share >= v_down then 'hold'
                     when mv.level <= mv.floor_pct then 'floor'
                     else 'down' end as k
           from mv),
  fin as (select dc.*,
                 -- a jump is a move down (since 23 Oct), so existing readers keep working; ladder_kind says which (a revert
                 -- on the fare plan, recorded before 26 Oct, is a move up)
                 case dc.k when 'planned' then case dc.plan_move when 'jump' then 'down' when 'revert' then 'up' else dc.plan_move end
                           when 'up' then 'up' when 'down' then 'down' when 'ul_jump' then 'down' else 'hold' end as move,
                 case dc.k when 'planned' then dc.plan_move when 'up' then 'up' when 'down' then 'down' when 'ul_jump' then 'jump'
                           else 'hold' end as ladder_kind,
                 case dc.k when 'planned' then dc.plan_level
                           when 'up' then least(dc.level + v_step, dc.cap_pct)
                           when 'down' then greatest(dc.level - v_step, dc.floor_pct)
                           when 'ul_jump' then dc.next_level
                           else dc.level end as new_level,
                 -- a cut-or-keep decision for Gitesh (since 23 Oct; by loads since 26 Oct): due at the last jump level and
                 -- held there this Saturday under fare_ladder_down_share sold out (or that hold put on the fare plan this
                 -- week), or marked so before (a hold recorded after the jump); it stays marked, whatever holds it, until it
                 -- climbs (a step up this Saturday, or on the fare plan)
                 coalesce(dc.ul_state = 'due' and dc.next_level is null
                          and (dc.k = 'ul_decide' or (dc.k = 'planned' and dc.uk = 'ul_decide') or dc.ul_marked)
                          and dc.k <> 'up' and not (dc.k = 'planned' and dc.plan_move is not distinct from 'up'), false) as decide,
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
                   when 'held_up' then format('held after a step up on %s', to_char(fin.up_on, 'FMDD Mon'))
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
                   -- under launch (since 23 Oct; spec §2)
                   when 'ul_jump' then case when fin.ul_state = 'due'
                     then format('at %s%% since %s: sold out %s of %s: to %s%% for %s', trim_scale(fin.level), to_char(fin.jumped_on, 'FMDD Mon'),
                                 fin.sold, fin.n, trim_scale(fin.next_level), v_ul_span)
                     else format('%s%% full over %s days at launch: to %s%% for %s', round(fin.w_load), trim_scale(v_ul_days), trim_scale(fin.next_level), v_ul_span) end
                   when 'ul_full' then case when fin.jw_load is null
                     then format('at %s%% since %s: sold out %s of %s, no flights in the last %s days: holds at %s%%', trim_scale(fin.level),
                                 to_char(fin.jumped_on, 'FMDD Mon'), fin.sold, fin.n, trim_scale(v_ul_days), trim_scale(fin.level))
                     else format('at %s%% since %s: sold out %s of %s but %s%% full over %s days: holds at %s%%, judged again next Saturday', trim_scale(fin.level),
                                 to_char(fin.jumped_on, 'FMDD Mon'), fin.sold, fin.n, round(fin.jw_load), trim_scale(v_ul_days), trim_scale(fin.level)) end
                   when 'ul_hold' then format('at %s%% since %s: judged on %s', trim_scale(fin.level), to_char(fin.jumped_on, 'FMDD Mon'), to_char(fin.judge_on, 'FMDD Mon'))
                   when 'ul_decide' then format('at %s%% since %s: sold out %s of %s: holds at %s%%; cut or keep? (Saturday review)',
                                                trim_scale(fin.level), to_char(fin.jumped_on, 'FMDD Mon'), fin.sold, fin.n, trim_scale(fin.level))
                   when 'ul_few' then format('sold out %s of %s, at %s: %s flight%s in %s days, needs %s to jump', fin.sold, fin.n, fin.floor_words, fin.w_n,
                                             case when fin.w_n = 1 then '' else 's' end, trim_scale(v_ul_days), trim_scale(v_ul_min))
                   when 'ul_since' then format('sold out %s of %s, at %s since %s: may jump from %s', fin.sold, fin.n, fin.floor_words,
                                               to_char(fin.launch_since, 'FMDD Mon'), to_char(fin.launch_since + v_ul_days::int, 'FMDD Mon'))
                   when 'ul_climb' then 'under launch: climbs or holds only'
                   else format('sold out %s of %s, at %s', fin.sold, fin.n, fin.floor_words) end as reason,
                 -- the level the game should show: this week's, once the captures see it
                 case when fin.plan_id is not null and fin.applied then fin.new_level else fin.level end as expect
            from fin),
  -- the fare index: each flight of the latest captured day as a % of the default price (against the market's default, or
  -- the inferred baseline times the launch level: latest's ratios); the day's average to 0.1, and the flight furthest from
  -- the level the game should show. inferred_index: the same day read the old way (against the inferred baseline), kept
  -- to compare (spec §4)
  ix as (select od.*,
                (select round(avg(r), 1) from unnest(od.ratios) r) as fare_index,
                (select r from unnest(od.ratios) r order by abs(r - od.expect) desc limit 1) as worst,
                (select round(avg(r), 1) from unnest(od.inf) r) as inferred_index
           from od),
  fx as (select ix.*,
                case when ix.worst is not null then abs(ix.worst - ix.expect) <= 1 end as matches,
                -- set back (manual §5, since 21 Oct): off its level, not on the fare plan this week, not new, and captured
                -- since its newest rotation launched
                coalesce(ix.worst is not null and abs(ix.worst - ix.expect) > 1 and ix.plan_id is null and not ix.young
                         and (ix.last_day is null or ix.latest_on > ix.last_day), false) as fix
           from ix)
  select coalesce(jsonb_agg(jsonb_build_object(
           -- since 26 Oct a row per direction: out from the route's hub, back to it, with its airports that way round
           'route_id', o.route_id, 'hub', o.hub, 'dest', o.dest, 'direction', o.dir, 'from', o.dir_from, 'to', o.dir_to, 'cabin', o.cabin,
           'departures', o.n, 'sold_out', o.sold, 'sold_out_share', round(o.share, 1), 'load', round(o.load_week, 1), 'average_fare', round(o.fare_week, 2),
           'baseline_fare', round(o.baseline_fare, 2), 'baseline_on', o.baseline_on, 'latest_fare', round(o.latest_fare, 2), 'latest_on', o.latest_on,
           'fare_index', o.fare_index, 'index_matches', o.matches,
           -- since 4 Nov: market (baseline_fare is the game's default price, read on default_on) or inferred (no market read
           -- of that direction yet: the first captured fare as before); the inferred index beside it, to compare
           'default_source', o.default_source, 'default_on', o.default_on, 'inferred_index', o.inferred_index,
           'level', trim_scale(o.level), 'recorded', o.recorded, 'steps', trim_scale(round((o.level - v_launch) / v_step, 1)),
           'move', o.move, 'new_level', trim_scale(o.new_level), 'new_steps', trim_scale(round((o.new_level - v_launch) / v_step, 1)),
           'change_pct', case when o.level > 0 then trim_scale(round((o.new_level / o.level - 1) * 100, 1)) end,
           'reason', o.reason, 'contested', o.contested, 'floor', trim_scale(o.floor_pct), 'cap', trim_scale(o.cap_pct), 'new_route', o.young,
           'planned', o.plan_id is not null, 'plan_id', o.plan_id, 'applied', o.applied, 'seen_on', o.seen_on,
           -- what Put on the fare plan writes: every level that changes (jumps included), a hold that follows a step down,
           -- and since 26 Oct the first cut-or-keep hold under launch (so the mark stays)
           'to_plan', o.plan_id is null and ((o.move in ('up', 'down') and o.new_level <> o.level) or o.k = 'held' or (o.k = 'ul_decide' and not o.ul_marked)),
           -- under launch (since 23 Oct): what Put on the fare plan writes as ladder_move, the cabin's state with its
           -- figures, and whether it is a cut-or-keep decision for Gitesh
           'ladder_kind', o.ladder_kind,
           'under_launch', case when o.ul_state is not null then jsonb_strip_nulls(jsonb_build_object(
             'state', o.ul_state,
             'window_load', round(case when o.ul_state = 'launch' then o.w_load else o.j_load end, 1),
             'window_flights', case when o.ul_state = 'launch' then o.w_n else o.j_n end,
             'jumped_on', o.jumped_on, 'judge_on', o.judge_on,
             -- since 2 Nov: the window a cabin due is judged on (the last fare_under_launch_days since the jump)
             'judged_load', case when o.ul_state = 'due' then round(o.jw_load, 1) end,
             'judged_flights', case when o.ul_state = 'due' then o.jw_n end)) end,
           'decide', o.decide,
           -- a change that sets it back to its level (manual §5, since 21 Oct)
           'fix', o.fix,
           'fix_reason', case when o.fix then format('captured fare at %s%%, level %s%%', trim_scale(round(o.worst, 1)), trim_scale(o.expect)) end)
           order by o.hub, o.dest, o.dir = 'back', o.cabin desc), '[]'::jsonb)
    into v_rows from fx o;

  -- the game's Ticket price adjustments, route by route only (manual §5, since 21 Oct: never a whole base, so a route
  -- under 7 days old is never touched). Each sets the level with the baseline default price. Since 26 Oct each direction
  -- has its own level, so each direction is an action of its own (From A to B, From B to A). First the set-back changes
  -- (fix), then the week's moves, each in the rows' order (hub, dest, out before back): for each direction, when both
  -- cabins go to the same level, one action with both classes ticked; otherwise one for each cabin, economy first. A
  -- direction whose levels don't change gets no action.
  for v_r in select x.fix, x.hub, x.dest, x.dir_from, x.dir_to,
                    jsonb_agg(jsonb_build_object('cabin', x.cabin, 'level', x.level, 'reason', x.reason) order by x.cabin = 'business') as moves
               from (select true as fix, e ->> 'route_id' as route_id, e ->> 'hub' as hub, e ->> 'dest' as dest, e ->> 'direction' as dir,
                            e ->> 'from' as dir_from, e ->> 'to' as dir_to, e ->> 'cabin' as cabin,
                            (e ->> 'level')::numeric as level, e ->> 'fix_reason' as reason
                       from jsonb_array_elements(v_rows) e
                      where (e ->> 'fix')::boolean
                     union all
                     select false, e ->> 'route_id', e ->> 'hub', e ->> 'dest', e ->> 'direction', e ->> 'from', e ->> 'to', e ->> 'cabin',
                            (e ->> 'new_level')::numeric, null
                       from jsonb_array_elements(v_rows) e
                      where (e ->> 'new_level')::numeric <> (e ->> 'level')::numeric) x
              group by x.fix, x.route_id, x.hub, x.dest, x.dir, x.dir_from, x.dir_to
              order by x.fix desc, x.hub, x.dest, x.dir = 'back' loop
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
      v_n := v_n + 1;
      v_actions := v_actions || jsonb_build_object(
        'n', v_n, 'route', v_r.hub || '–' || v_r.dest, 'classes', v_change -> 'classes', 'from', v_r.dir_from, 'to', v_r.dir_to,
        'level', trim_scale(v_lv), 'sign', case when v_lv >= 100 then '+' else '-' end, 'pct', trim_scale(abs(v_lv - 100)),
        'baseline', 'default price', 'fix', v_r.fix, 'reason', v_change ->> 'reason',
        'text', format('From %s to %s: %s%s%% of the default price, %s', v_r.dir_from, v_r.dir_to,
                       case when v_lv >= 100 then '+' else '−' end, trim_scale(abs(v_lv - 100)), v_words));
    end loop;
  end loop;

  return jsonb_build_object(
    'airline_id', p_airline_id, 'as_of', private.fig_ts(p_as_of), 'week_of', v_week,
    'from', private.fig_ts(p_as_of - interval '7 days'), 'to', private.fig_ts(p_as_of),
    'settings', jsonb_build_object('step_pts', v_step, 'up_share', v_up, 'down_share', v_down, 'min_departures', v_min,
                                   'hold_weeks', v_hold, 'up_hold_weeks', v_up_hold, 'cap_pts', v_cap, 'launch_pct', v_launch, 'cap_pct', v_launch + v_cap,
                                   'floor_pct', v_floor, 'new_route_days', v_new_days, 'capacity_hold_days', v_added_days,
                                   'baseline_day', v_base_day,
                                   'under_launch', jsonb_build_object('load_pct', v_ul_load, 'levels', to_jsonb(v_ul_levels), 'days', v_ul_days,
                                                                      'min_flights', v_ul_min)),
    'scan', case when v_scan is null then null else jsonb_build_object('id', v_scan, 'taken_at', private.fig_ts(v_scan_at)) end,
    'moves', jsonb_build_object(
      'up', (select count(*) from jsonb_array_elements(v_rows) e where e ->> 'move' = 'up'),
      'hold', (select count(*) from jsonb_array_elements(v_rows) e where e ->> 'move' = 'hold'),
      'down', (select count(*) from jsonb_array_elements(v_rows) e where e ->> 'move' = 'down'),
      'jumps', (select count(*) from jsonb_array_elements(v_rows) e where e ->> 'ladder_kind' = 'jump'),
      'decisions', (select count(*) from jsonb_array_elements(v_rows) e where (e ->> 'decide')::boolean)),
    'to_plan', (select count(*) from jsonb_array_elements(v_rows) e where (e ->> 'to_plan')::boolean),
    'planned', (select count(*) from jsonb_array_elements(v_rows) e where (e ->> 'planned')::boolean),
    -- since 26 Oct the directions set back (a route and direction each)
    'off_level', (select count(distinct (e ->> 'route_id') || ' ' || (e ->> 'direction')) from jsonb_array_elements(v_rows) e where (e ->> 'fix')::boolean),
    'routes', v_rows, 'actions', v_actions,
    'notes', jsonb_build_array(
      'Since 4 Nov the fare index measures each flight of the latest captured day against the game''s default price, read each week from the Market Analysis page (default_source market); where the market pages haven''t read a direction yet (default_source inferred), it compares each flight with its direction''s fare on 21 Oct 2026, when every route was at its launch level (or its first captured fare, for a route launched later), times the launch level, as before. Since 26 Oct each direction has its own level, judged on its own flights: a direction more than 1 point off its level gets a change that sets it back, first in the list, unless it''s on the fare plan this week, its route is new, or it isn''t captured since its route''s newest flight launched.'));
end
$function$

;


-- ============================================================ 5. who may call them
revoke all on function private.fig_default_prices(bigint, timestamptz) from public, anon, authenticated, service_role;
revoke all on function public.default_prices(bigint, timestamptz) from public, anon, authenticated, service_role;
grant execute on function public.default_prices(bigint, timestamptz) to authenticated;

-- ============================================================ 6. descriptions
comment on function private.fig_default_prices(bigint, timestamptz) is 'The game''s default price for each of an airline''s routes, direction and cabin (since 4 Nov; spec docs/specs/2026-11-04-fare-default-from-market.md §2), with no check of its own: for each route not removed (route_id, hub, dest), direction (out from the hub, back to it; origin and destination, its airports that way round) and cabin (economy from class Y, business from C), the default and current price (market_prices) of the latest market run finished by p_as_of (status done, finished_at) that read that direction ok with the airline open (market_reads.airline_id; a pair two of our airlines fly is read once, under the first, so the other has none), the run''s id and date (run_on, its start''s UTC date), when the page was read, and the default of the run before that read it (previous_default, previous_run_on; null when there is none). Read by default_prices() and private.fig_fare_ladder().';
comment on function public.default_prices(bigint, timestamptz) is 'The game''s default price on an airline''s routes, as the market pages read it (since 4 Nov; spec docs/specs/2026-11-04-fare-default-from-market.md §2): prices, one row per route, direction and cabin the market pages have read (private.fig_default_prices()), ordered hub, dest, out before back, economy first: route_id, hub, dest, direction, from, to, cabin, default_price and current_price (AS$, from the latest finished market run by the moment that read it; the current price is the highest of our flights that way), current_pct (current ÷ default, % to 0.1), run_id, run_on, read_at, previous_default and previous_run_on (the run before it that read it) and default_changed (true when the two defaults differ). Small: no statement limit of its own. Staff only; runs as owner and checks the caller itself.';

do $describe$
declare x record; d text;
begin
  for x in select * from (values
      ('private.market_ingest(bigint, text, jsonb)', 'pricing [{class, current, default}]',
       ' Since 4 Nov (capture 1.11, spec docs/specs/2026-11-04-fare-default-from-market.md) a page also takes pricing [{class, current, default}] (each class Y, C, F or Cargo once, both prices numbers above 0, AS$), the page''s Pricing panel, written to market_prices for our airline; a page sent again replaces its prices; a page without pricing writes none; a page answers prices, how many it wrote.'),
      ('public.capture_market(text, text, jsonb)', 'pricing (the page''s Pricing panel',
       ' Since 4 Nov (capture 1.11, spec docs/specs/2026-11-04-fare-default-from-market.md) a page may carry pricing (the page''s Pricing panel: each class''s current and default price, kept in market_prices) and answers prices too.'),
      ('private.fig_fare_ladder(bigint, timestamptz)', 'default price (since 4 Nov',
       ' A direction''s fare index is measured against the game''s default price (since 4 Nov, spec docs/specs/2026-11-04-fare-default-from-market.md §3) where the market pages have read it (private.fig_default_prices()); elsewhere against the inferred baseline as before.'),
      ('public.fare_ladder(bigint, timestamptz)', 'Since 4 Nov (spec docs/specs/2026-11-04-fare-default-from-market.md §3) a direction',
       ' Since 4 Nov (spec docs/specs/2026-11-04-fare-default-from-market.md §3) a direction''s captured fares are measured against the game''s default price where the market pages have read it (default_prices(), the latest finished market run by the moment that read that direction with the airline open): fare_index is the latest captured day''s fares ÷ the default × 100 (to 0.1), each flight compared with the level the same way for the set-back (more than a point off: one change for the direction at its level), baseline_fare the default price, baseline_on and default_on the run''s date, default_source market. Where there is no market read of the direction yet, default_source is inferred and everything reads as before (the first captured fare, times the launch level). inferred_index gives the latest day read the old way, beside it. The levels, the moves, the cap, the floor and the jumps are unchanged.')
    ) v(f, mark, more) loop
    d := obj_description(x.f::regprocedure, 'pg_proc');
    if position(x.mark in coalesce(d, '')) = 0 then
      execute format('comment on function %s is %L', x.f, coalesce(d, '') || x.more);
    end if;
  end loop;
end
$describe$;

select set_config('equinox.actor', '', true), set_config('equinox.actor_detail', '', true);

-- Rivals' fleets in the world scan (23 Oct 2026; spec docs/specs/2026-10-23-rival-fleets.md, option A of brief
-- docs/briefs/2026-10-23-rival-fleets.md; the manual's decided entry "To build: rivals' fleets in the world scan").
--
-- Why (Gitesh, 23 Oct): the scan reads schedules and airports only, so a rival's fleet and order book never showed:
-- Icelandair (enterprise 101) flies 186 flights a week with 99 aircraft and 44 on order. Each evening's scan (Capture all
-- airlines 1.8, and scripts/scanner/gscan.py by hand) now also reads every enterprise's overview page and sends it as a
-- new kind, fleet; competition() shows each rival's fleet with the change since the week-before scan, and flags big
-- order books and airlines with orders but no flights yet.
--
-- Adds two tables, two settings and two internal functions, and replaces five functions with the same arguments (CREATE
-- OR REPLACE); drops and renames nothing and changes no data, so it can be applied from the chat. It doesn't touch the
-- fare ladder (private.fig_fare_ladder), which another change is replacing at the same time.
--   1. public.scan_airline_fleet: one row per scan, airline and aircraft type, as the overview page's Fleet table gives it
--      (owned, leased, overall, leased out, on offer, on order, average age). public.scan_airline_profile: one row per
--      scan and airline read, with the totals (fleet size, on order, average age), the general figures (stations, staff,
--      passengers, alliance, parent company's game id, founded) and whether the page read (read_ok, note). Both kept for
--      good with the scan summaries (the monthly archive doesn't touch them). RLS on with no rule and no access for anon
--      or authenticated (manual §1): read through functions only.
--   2. settings rival_orders_flag_pct 25 and rival_orders_flag_min 5, in every world, described.
--   3. private.scan_ingest() takes kind fleet (the airline placed as the scan places airlines, private.scan_airline());
--      capture_scan() and ingest_snapshot() accept it.
--   4. private.scan_fleet() (an airline's fleet in a scan against the week-before scan) and private.scan_order_flags()
--      (the world's big order books and airlines starting with orders, for one of our airlines), both internal;
--      private.fig_competition() (so competition() and the briefing) gives each competitor and rival profile its fleet
--      and the answer the world-wide order_flags; private.fig_export() carries order_flags beside each airline's
--      competitors for the weekly report; system_status()'s scan says how many fleet pages the latest scan read.
-- No flag feeds the openings, the contested test or the fare pause: nothing else in those functions changes.

select set_config('equinox.actor', 'migration', true),
       set_config('equinox.actor_detail', '20261023120000_rival_fleets', true);

-- ============================================================ 1. the tables
create table public.scan_airline_fleet (
  scan_id bigint not null,
  world_id bigint not null,
  airline_id bigint not null,
  type_name text not null,
  game_type_id integer,
  owned integer,
  leased integer,
  overall integer,
  leased_out integer,
  on_offer integer,
  on_order integer,
  avg_age_years numeric(5,1),
  primary key (scan_id, airline_id, type_name),
  constraint scan_airline_fleet_scan_world_fkey foreign key (scan_id, world_id) references public.game_scans (id, world_id) on delete cascade,
  constraint scan_airline_fleet_airline_fkey foreign key (airline_id, world_id) references public.airlines (id, world_id)
);
create index scan_airline_fleet_airline_scan_idx on public.scan_airline_fleet (airline_id, scan_id);
create index scan_airline_fleet_airline_world_idx on public.scan_airline_fleet (airline_id, world_id);

create table public.scan_airline_profile (
  scan_id bigint not null,
  world_id bigint not null,
  airline_id bigint not null,
  fleet_size integer,
  on_order integer,
  avg_age_years numeric(5,1),
  stations integer,
  staff integer,
  passengers bigint,
  alliance text,
  parent_game_id integer,
  founded date,
  read_ok boolean not null,
  note text,
  read_at timestamp with time zone not null default now(),
  primary key (scan_id, airline_id),
  constraint scan_airline_profile_scan_world_fkey foreign key (scan_id, world_id) references public.game_scans (id, world_id) on delete cascade,
  constraint scan_airline_profile_airline_fkey foreign key (airline_id, world_id) references public.airlines (id, world_id)
);
create index scan_airline_profile_airline_scan_idx on public.scan_airline_profile (airline_id, scan_id);
create index scan_airline_profile_airline_world_idx on public.scan_airline_profile (airline_id, world_id);

alter table public.scan_airline_fleet enable row level security;
alter table public.scan_airline_profile enable row level security;
revoke all on table public.scan_airline_fleet, public.scan_airline_profile from public, anon, authenticated;

-- ============================================================ 2. the settings
insert into public.settings (world_id, airline_id, key, value, unit, description, since, reason)
select w.id, null, x.key, x.value, x.unit, x.description, date '2026-10-23', x.reason
  from public.worlds w
 cross join (values
   ('rival_orders_flag_pct', '25'::jsonb, '%',
    'A big order book (competition()''s order_flags, kind orders; spec docs/specs/2026-10-23-rival-fleets.md §4): a rival whose aircraft on order, on its overview page in the latest world scan, are at least this share of its fleet, and at least rival_orders_flag_min. Shown on Competition''s Order books and in the weekly report''s risks; feeds nothing else (no opening, contested test or fare pause). Raise it to 35 if it flags many rivals at once (the brief).',
    'Gitesh, 23 Oct (brief docs/briefs/2026-10-23-rival-fleets.md, option A): a quarter more aircraft on the way; Icelandair at 44% is flagged, an airline replacing a few old aircraft (5 of 40, 12%) isn''t'),
   ('rival_orders_flag_min', '5'::jsonb, 'aircraft',
    'A big order book (competition()''s order_flags, kind orders): the fewest aircraft on order to flag, with rival_orders_flag_pct, so a 4-aircraft start-up ordering 1 doesn''t show. An airline with aircraft on order and no flights in the scan is flagged as starting whatever the number.',
    'Gitesh, 23 Oct (brief docs/briefs/2026-10-23-rival-fleets.md, option A)')) x(key, value, unit, description, reason)
on conflict on constraint settings_world_airline_key_key do nothing;

-- ============================================================ 3. the overview pages, stored
CREATE OR REPLACE FUNCTION private.scan_ingest(p_world_id bigint, p_kind text, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare v_world bigint; v_scan bigint; v_al bigint; v_res jsonb; n int := 0; v_err text; t jsonb;
begin
  if p_kind is null or p_kind not in ('start', 'airline', 'airport', 'finish', 'markets', 'fleet') then raise exception 'unknown kind'; end if;
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
    elsif p_kind = 'fleet' then
      -- one airline's overview page (spec docs/specs/2026-10-23-rival-fleets.md §2, §3): {snapshot_id, enterprise_id, name,
      -- types: [{type, type_id, owned, leased, overall, leased_out, on_offer, on_order, avg_age_years}], totals: {...},
      -- profile: {code, alliance, alliance_id, headquarters, parent_id, parent, founded, passengers, stations, fleet_size,
      -- staff}}, or error in place of the rows when the page didn't read. The airline is placed as the scan places airlines.
      if coalesce(p_payload ->> 'enterprise_id', '') !~ '^\d{1,9}$' then raise exception 'fleet: no enterprise_id'; end if;
      v_al := private.scan_airline(v_world, (p_payload ->> 'enterprise_id')::int, p_payload ->> 'name');
      v_err := case when p_payload ? 'error' then left(coalesce(nullif(btrim(p_payload ->> 'error'), ''), 'no reason given'), 300)
                    when jsonb_typeof(p_payload -> 'types') is distinct from 'array' then 'no types list' end;
      if v_err is not null then
        -- a page that didn't read: kept as such, unless the same scan already read it
        insert into public.scan_airline_profile as x (scan_id, world_id, airline_id, read_ok, note)
        values (v_scan, v_world, v_al, false, v_err)
        on conflict (scan_id, airline_id) do update set note = excluded.note, read_at = now() where not x.read_ok;
        v_res := jsonb_build_object('ok', true, 'read_ok', false, 'rows', 0);
      else
        delete from public.scan_airline_fleet where scan_id = v_scan and airline_id = v_al;
        for t in select x from jsonb_array_elements(p_payload -> 'types') x loop
          if nullif(btrim(t ->> 'type'), '') is null then continue; end if;
          insert into public.scan_airline_fleet as f (scan_id, world_id, airline_id, type_name, game_type_id, owned, leased, overall,
                                                      leased_out, on_offer, on_order, avg_age_years)
          values (v_scan, v_world, v_al, left(btrim(t ->> 'type'), 120), private.json_int(t -> 'type_id'), private.json_int(t -> 'owned'),
                  private.json_int(t -> 'leased'), private.json_int(t -> 'overall'), private.json_int(t -> 'leased_out'),
                  private.json_int(t -> 'on_offer'), private.json_int(t -> 'on_order'), round(private.json_num(t -> 'avg_age_years'), 1))
          on conflict (scan_id, airline_id, type_name) do update set game_type_id = excluded.game_type_id, owned = excluded.owned,
            leased = excluded.leased, overall = excluded.overall, leased_out = excluded.leased_out, on_offer = excluded.on_offer,
            on_order = excluded.on_order, avg_age_years = excluded.avg_age_years;
          n := n + 1;
        end loop;
        insert into public.scan_airline_profile as x (scan_id, world_id, airline_id, fleet_size, on_order, avg_age_years, stations, staff,
                                                      passengers, alliance, parent_game_id, founded, read_ok, note)
        values (v_scan, v_world, v_al,
                coalesce(private.json_int(p_payload #> '{totals,overall}'), private.json_int(p_payload #> '{profile,fleet_size}')),
                private.json_int(p_payload #> '{totals,on_order}'), round(private.json_num(p_payload #> '{totals,avg_age_years}'), 1),
                private.json_int(p_payload #> '{profile,stations}'), private.json_int(p_payload #> '{profile,staff}'),
                private.json_int(p_payload #> '{profile,passengers}'), left(nullif(btrim(p_payload #>> '{profile,alliance}'), ''), 120),
                private.json_int(p_payload #> '{profile,parent_id}'),
                case when (p_payload #>> '{profile,founded}') ~ '^\d{4}-\d{2}-\d{2}$' then (p_payload #>> '{profile,founded}')::date end,
                true, null)
        on conflict (scan_id, airline_id) do update set fleet_size = excluded.fleet_size, on_order = excluded.on_order,
          avg_age_years = excluded.avg_age_years, stations = excluded.stations, staff = excluded.staff, passengers = excluded.passengers,
          alliance = excluded.alliance, parent_game_id = excluded.parent_game_id, founded = excluded.founded, read_ok = true, note = null,
          read_at = now();
        v_res := jsonb_build_object('ok', true, 'read_ok', true, 'rows', n);
      end if;
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

CREATE OR REPLACE FUNCTION public.ingest_snapshot(p_secret text, p_kind text, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_res jsonb;
  v_actor text := current_setting('equinox.actor', true); v_detail text := current_setting('equinox.actor_detail', true);
begin
  if not exists (select 1 from public.ingest_secret s where s.secret = p_secret) then raise exception 'not allowed'; end if;
  if p_kind is null or p_kind not in ('start', 'airline', 'airport', 'finish', 'markets', 'fleet') then raise exception 'unknown kind'; end if;
  perform set_config('equinox.actor', coalesce(nullif(v_actor, ''), 'script'), true),
          set_config('equinox.actor_detail', coalesce(nullif(v_detail, ''), 'ingest_snapshot'), true);
  -- the work is shared with the capture's scan (capture_scan()); a start scans the default world
  v_res := private.scan_ingest(null, p_kind, p_payload);
  perform set_config('equinox.actor', coalesce(v_actor, ''), true), set_config('equinox.actor_detail', coalesce(v_detail, ''), true);
  return v_res;
end
$function$;

CREATE OR REPLACE FUNCTION public.capture_scan(p_key text, p_kind text, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_world bigint; v_scan bigint; v_res jsonb;
  v_actor text := current_setting('equinox.actor', true); v_detail text := current_setting('equinox.actor_detail', true);
begin
  v_world := private.capture_key_world(p_key);
  if v_world is null then return jsonb_build_object('ok', false, 'error', 'bad key'); end if;
  if p_kind is null or p_kind not in ('start', 'airline', 'airport', 'finish', 'fleet') then
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

-- ============================================================ 4. the figures
-- an airline's fleet in a scan, against the week-before scan: null when the scan didn't read its overview page
create or replace function private.scan_fleet(p_scan_id bigint, p_before_id bigint, p_airline_id bigint)
 returns jsonb
 language sql
 stable
 set search_path to ''
as $function$
  with p as (select x.* from public.scan_airline_profile x where x.scan_id = p_scan_id and x.airline_id = p_airline_id and x.read_ok),
  b as (select x.* from public.scan_airline_profile x where x.scan_id = p_before_id and x.airline_id = p_airline_id and x.read_ok)
  select jsonb_build_object(
           'overall', p.fleet_size, 'on_order', p.on_order, 'avg_age_years', p.avg_age_years,
           'types_count', (select count(*) from public.scan_airline_fleet f where f.scan_id = p_scan_id and f.airline_id = p_airline_id)::int,
           'types', (select coalesce(jsonb_agg(jsonb_build_object('type', t.type_name, 'overall', t.overall, 'on_order', t.on_order,
                                                                  'avg_age_years', t.avg_age_years)
                                               order by coalesce(t.overall, 0) desc, coalesce(t.on_order, 0) desc, t.type_name), '[]'::jsonb)
                       from (select f.* from public.scan_airline_fleet f where f.scan_id = p_scan_id and f.airline_id = p_airline_id
                              order by coalesce(f.overall, 0) desc, coalesce(f.on_order, 0) desc, f.type_name limit 5) t),
           'overall_before', b.fleet_size, 'on_order_before', b.on_order,
           'overall_change', p.fleet_size - b.fleet_size, 'on_order_change', p.on_order - b.on_order)
    from p left join b on true
$function$;

-- the world's big order books and airlines starting with orders in a scan (spec docs/specs/2026-10-23-rival-fleets.md §4):
-- the same list for every one of our airlines, each marked whether the airline flies on p_airline_id's city pairs or
-- at its bases
create or replace function private.scan_order_flags(p_airline_id bigint, p_scan_id bigint, p_before_id bigint, p_pairs text[])
 returns jsonb
 language plpgsql
 stable
 set search_path to ''
as $function$
declare
  w bigint := private.fig_airline_world(p_airline_id);
  -- the world's own rows (not an airline's), so every airline's answer has the same list
  v_pct numeric := private.fig_num(w, null, 'rival_orders_flag_pct');
  v_min numeric := private.fig_num(w, null, 'rival_orders_flag_min');
  v_res jsonb;
begin
  if p_scan_id is null then return '[]'::jsonb; end if;
  with c as (
    -- every rival whose overview page the scan read, with aircraft on order
    select p.airline_id, p.fleet_size, p.on_order, coalesce(ra.public_name, ra.game_name, ra.planner_name, 'airline ' || p.airline_id) as name
      from public.scan_airline_profile p
      join public.airlines ra on ra.id = p.airline_id
      left join public.groups g on g.id = ra.group_id
     where p.scan_id = p_scan_id and p.read_ok and coalesce(p.on_order, 0) > 0 and coalesce(g.kind, 'rival') <> 'ours'),
  -- each one's flights in the scan: all of them, and passenger flights (private.scan_passenger(), the weekly report's
  -- rule); null when the scan holds no schedule for it
  fx as (
    select sc.airline_id, f ->> 2 as origin, f ->> 3 as dest, length(regexp_replace(coalesce(f ->> 4, ''), '[^1-7]', '', 'g')) as n,
           private.scan_passenger(f ->> 7) as pax
      from public.game_scan_schedules sc
      cross join lateral jsonb_array_elements(case when jsonb_typeof(sc.flights) = 'array' then sc.flights else '[]'::jsonb end) f
     where sc.scan_id = p_scan_id and sc.airline_id in (select c.airline_id from c) and jsonb_typeof(f) = 'array'),
  fl as (
    select c.*,
           case when exists (select 1 from public.game_scan_schedules sc where sc.scan_id = p_scan_id and sc.airline_id = c.airline_id)
                then (select coalesce(sum(x.n), 0) from fx x where x.airline_id = c.airline_id)::int end as weekly_all,
           (select coalesce(sum(x.n) filter (where x.pax), 0) from fx x where x.airline_id = c.airline_id)::int as weekly,
           exists (select 1 from fx x where x.airline_id = c.airline_id and x.pax and x.n > 0
                      and least(x.origin, x.dest) || '-' || greatest(x.origin, x.dest) = any (coalesce(p_pairs, '{}'::text[]))) as on_pairs,
           exists (select 1 from public.scan_airline_airports a
                    where a.scan_id = p_scan_id and a.airline_id = c.airline_id and a.weekly_departures > 0
                      and a.airport_code in (select b.airport_code from public.airline_bases b
                                              where b.airline_id = p_airline_id and b.role <> 'station')) as at_bases
      from c),
  k as (
    select fl.*,
           case when fl.weekly_all = 0 then 'starting'
                when fl.on_order >= v_min and fl.on_order * 100.0 >= v_pct * coalesce(fl.fleet_size, 0) then 'orders' end as kind
      from fl
     -- freighters only (flights, none of them passenger flights) are no one's rivals
     where not (coalesce(fl.weekly_all, 0) > 0 and fl.weekly = 0))
  select coalesce(jsonb_agg(jsonb_build_object(
           'airline_id', k.airline_id, 'name', k.name, 'kind', k.kind, 'fleet', k.fleet_size, 'on_order', k.on_order,
           'share', round(100.0 * k.on_order / nullif(k.fleet_size, 0), 1), 'weekly', k.weekly_all,
           'on_order_change', fc.d -> 'on_order_change', 'fleet_change', fc.d -> 'overall_change',
           'on_pairs', k.on_pairs, 'at_bases', k.at_bases, 'meets', k.on_pairs or k.at_bases,
           'words', case when k.kind = 'starting'
                         then format('%s: %s on order and no flights yet%s', k.name, k.on_order,
                                     case when coalesce(k.fleet_size, 0) > 0 then format(' (%s aircraft)', k.fleet_size) else '' end)
                         else format('%s: %s on order, %s%% of its %s aircraft', k.name, k.on_order,
                                     trim_scale(round(100.0 * k.on_order / nullif(k.fleet_size, 0), 1)), k.fleet_size) end)
           order by round(100.0 * k.on_order / nullif(k.fleet_size, 0), 1) desc nulls first, k.on_order desc, k.name, k.airline_id), '[]'::jsonb)
    into v_res
    from k
    cross join lateral (select private.scan_fleet(p_scan_id, p_before_id, k.airline_id) as d) fc
   where k.kind is not null;
  return v_res;
end
$function$;

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
  v_threats jsonb; v_body jsonb; v_group jsonb; v_flags jsonb;
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

  -- the world's big order books and airlines starting with orders (spec docs/specs/2026-10-23-rival-fleets.md §4), each
  -- marked whether it meets this airline (its city pairs or its bases); feeds nothing else here
  v_flags := private.scan_order_flags(p_airline_id, v_latest, v_before, v_pairs);

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
  -- our bases, every airline's (hubs and focus cities): a pair between two of them is a trunk (manual §4); a station
  -- (since 22 Oct, manual §2) is no base, so a pair with a station end is never a trunk
  ob as (select distinct b.airport_code from public.airline_bases b
           join public.airlines a on a.id = b.airline_id join public.groups g on g.id = a.group_id
          where b.world_id = w and g.kind = 'ours' and b.role <> 'station'),
  -- the other airlines of ours that have the pair on their own list (one airline per city pair, manual §2, decides)
  ol as (select least(r.hub_code, r.dest_code) as a, greatest(r.hub_code, r.dest_code) as b, array_agg(distinct al.iata_code order by al.iata_code) as codes
           from public.routes r join public.airlines al on al.id = r.airline_id join public.groups g on g.id = al.group_id
          where r.world_id = w and r.airline_id <> p_airline_id and not r.removed and g.kind = 'ours' and al.iata_code is not null
          group by 1, 2),
  -- at_base: from one of the airline's hubs or focus cities; at_station: from one of its stations (manual §2, since 22 Oct)
  op0 as (select distinct on (ro.a, ro.b) ro.*,
                 exists (select 1 from public.airline_bases b where b.airline_id = p_airline_id and b.airport_code = ro.hub and b.role <> 'station') as at_base,
                 exists (select 1 from public.airline_bases b where b.airline_id = p_airline_id and b.airport_code = ro.hub and b.role = 'station') as at_station,
                 -- in the trunk month only (trunk_month_from to trunk_month_to)
                 v_trunks and ro.hub in (select ob.airport_code from ob) and ro.dest in (select ob.airport_code from ob) as trunk
            from ro
           where not exists (select 1 from ourall o where o.a = ro.a and o.b = ro.b)
           order by ro.a, ro.b, (ro.hub = v_main) desc,
                    exists (select 1 from public.airline_bases b where b.airline_id = p_airline_id and b.airport_code = ro.hub and b.role <> 'station') desc,
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
  -- hubs first (manual §3), from the latest scan: the busiest rival at a base (a hub or focus city: a station is never
  -- contested), and each rival's departures a week from the base to the destination
  bt as (select x.airport_code, max(x.weekly_departures)::int as weekly from public.scan_airline_airports x
            join public.airlines ra on ra.id = x.airline_id left join public.groups g on g.id = ra.group_id
           where x.scan_id = v_latest and coalesce(g.kind, 'rival') <> 'ours'
             and x.airport_code in (select b.airport_code from public.airline_bases b where b.airline_id = p_airline_id and b.role <> 'station')
           group by 1),
  rt as (select ex.origin, ex.dest, max(ex.weekly)::int as weekly from ex where ex.scan_id = v_latest and ex.rival group by 1, 2),
  op2 as (select op1.*, bt.weekly as base_top, rt.weekly as route_top
            from op1 left join bt on bt.airport_code = op1.hub left join rt on rt.origin = op1.hub and rt.dest = op1.dest
           where op1.type_id is not null),
  op3 as (select op2.*,
                 -- hubs first is suspended for trunks in the trunk month (manual §4); a station opens nothing until the main
                 -- hub reaches its target, contested or not (manual §3, since 22 Oct): not at_base, so null below
                 case when op2.trunk then 'November trunk'
                      when v_exempt then 'exempt' when v_main is null then 'no main hub' when op2.hub = v_main then 'main hub'
                      when v_dep >= v_target then 'main hub at its target'
                      when not op2.at_base then null
                      when coalesce(op2.base_top, 0) > v_rival_weekly then 'contested base'
                      when coalesce(op2.route_top, 0) > 7 * v_rival_daily then 'contested route' end as allowed_by
            from op2),
  op4 as (select op3.*, op3.allowed_by is not null as allowed,
                 case when op3.allowed_by is not null then null
                      when op3.at_station then format('hubs first: stations wait for %s''s %s', v_main, trim_scale(v_target))
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
                                           group by 1 having sum(y.n) > 0 order by 2 desc, 1 limit 3) x),
             -- its fleet from its overview page (since 23 Oct, spec docs/specs/2026-10-23-rival-fleets.md §4)
             'fleet', private.scan_fleet(v_latest, v_before, pf.airline_id))
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
             'change_pct', round(100.0 * (n.weekly - o.weekly) / nullif(o.weekly, 0), 1),
             'fleet', private.scan_fleet(v_latest, v_before, cr.airline_id))
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
    'order_flags', v_flags,
    'notes', jsonb_build_array(
      'Rivals are every airline in the scan that isn''t one of ours; departures a week count each flight''s days, as gscan.py counts them, passenger flights only (freighters left out, as the weekly report counts). Our own now are the airline''s live legs; before, its flights in the week-before scan.',
      'From trunk_month_from to trunk_month_to (November, manual §4) the trunks, pairs between two of our bases (any of our airlines''), come first, shortest first: hubs first isn''t applied to them and no distance leaves one out. Whether a trunk makes sense stays the Scheduling chat''s judgment.',
      'The variant is the default line''s (manual §3): the smallest size the city''s stars allow (1–2 stars small, 3 small or mid, 4 small to large, 5 mid or large), bigger only for reach, the cheapest per seat whose range with a full load covers the distance, among the types the airline may buy; beyond every narrowbody the A350 that is cheapest per seat, and beyond 15,000 km the one with the most seats. A 1-star opening whose variant is the default small aircraft (the E195-E2) also names the small type with the fewest seats (variant_alt, the E190-E2, "or the E190-E2 if thin" in variant_note): the default line gives it to the thinnest 1-star city, and nothing in our data says how thin a city is, so the evening proposal decides.',
      'competitors (the weekly report''s, manual §7): the three rivals with the most departures a week on the city pairs the airline flies (its live legs, both ways) in the latest scan, ties by name; weekly and airports are each one''s whole passenger network in the latest scan, weekly_before in the week-before scan (none when that scan holds no schedule for it), the change against it as a number and a percent. self is the airline on the same terms, from the same scans'' schedules.',
      'fleet (each competitor''s and rival profile''s, since 23 Oct): from its overview page in the latest scan (scan_airline_fleet, scan_airline_profile): overall, on order, average age and its 5 biggest types, with the change in overall and on order against the week-before scan (null when either scan didn''t read its page); null when the latest scan didn''t read it. order_flags: every airline in the latest scan that isn''t one of ours, freighters only left out, with aircraft on order at least rival_orders_flag_pct of its fleet and at least rival_orders_flag_min (kind orders), or on order and no flights in the scan (kind starting); the same list for every airline, each marked on_pairs (it flies one of this airline''s city pairs), at_bases (it departs from one of its hubs or focus cities) and meets (either). No flag feeds the openings, the contested test or the fare pause.'));
end
$function$;

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
        'competitors', cp.d -> 'competitors', 'self', cp.d -> 'self', 'scans', cp.d -> 'scans',
        -- the world's flagged order books (since 23 Oct, spec docs/specs/2026-10-23-rival-fleets.md §5): the weekly report's risks
        'order_flags', cp.d -> 'order_flags') order by al.ord), '[]'::jsonb)
        from private.fig_airlines(p_world_id) al
        -- offset 0 keeps each document worked out once (folded into the outer query, each use would work it out again)
        cross join lateral (select private.fig_route_profit(al.airline_id, 1, p_as_of) as d offset 0) r1
        cross join lateral (select private.fig_route_profit(al.airline_id, 3, p_as_of) as d offset 0) r3
        cross join lateral (select private.fig_route_profit(al.airline_id, 7, p_as_of) as d offset 0) r7
        cross join lateral (select private.fig_competition(al.airline_id, p_as_of, 0) as d offset 0) cp));
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

-- ============================================================ 5. who may call them
revoke all on function private.scan_fleet(bigint, bigint, bigint) from public, anon, authenticated, service_role;
revoke all on function private.scan_order_flags(bigint, bigint, bigint, text[]) from public, anon, authenticated, service_role;

-- ============================================================ 6. descriptions
comment on table public.scan_airline_fleet is 'Each airline''s fleet by aircraft type in a world scan (since 23 Oct; spec docs/specs/2026-10-23-rival-fleets.md §3): one row per scan, airline and type as its overview page''s Fleet table shows it (/app/info/enterprises/<game id>), every enterprise the scan lists, flying or not. Kept for good, with the scan summaries (the monthly archive leaves it alone). Written by capture_scan() (Capture all airlines 1.8) and ingest_snapshot() (scripts/scanner/gscan.py, the fallback), kind fleet, through private.scan_ingest(); a later read in the same scan replaces the airline''s rows. Read by competition() (private.scan_fleet(), private.scan_order_flags()). RLS on with no rule: no access for anon or authenticated, read through functions (manual §1).';
comment on column public.scan_airline_fleet.type_name is 'The aircraft type as the page names it (the link''s text), e.g. Airbus A321XLR';
comment on column public.scan_airline_fleet.game_type_id is 'The game''s id for the type (the link''s aircraftsType?id=)';
comment on column public.scan_airline_fleet.owned is 'Aircraft of the type it owns';
comment on column public.scan_airline_fleet.leased is 'Aircraft of the type it leases';
comment on column public.scan_airline_fleet.overall is 'Aircraft of the type in its fleet (owned and leased)';
comment on column public.scan_airline_fleet.leased_out is 'Aircraft of the type it leases out to others';
comment on column public.scan_airline_fleet.on_offer is 'Aircraft of the type it offers for sale or lease';
comment on column public.scan_airline_fleet.on_order is 'Aircraft of the type on order, not yet delivered';
comment on column public.scan_airline_fleet.avg_age_years is 'The average age of the type''s aircraft, years (the page''s Ø age, "0.1 yrs")';
comment on table public.scan_airline_profile is 'Each airline''s overview page in a world scan (since 23 Oct; spec docs/specs/2026-10-23-rival-fleets.md §3): one row per scan and airline read, with the Fleet table''s totals (fleet_size, on_order, avg_age_years, from its tfoot) and the page''s General Information and General statistics, or read_ok false with the reason in note when the page didn''t read (a failed page never stops the scan). Kept for good, with the scan summaries. Written by capture_scan() and ingest_snapshot(), kind fleet, through private.scan_ingest(). Read by competition() (each rival''s fleet and the order flags) and system_status() (the fleet pages the latest scan read). RLS on with no rule: no access for anon or authenticated, read through functions (manual §1).';
comment on column public.scan_airline_profile.fleet_size is 'Aircraft in its fleet: the Fleet table''s overall total (the page''s Fleet size when the table has no totals)';
comment on column public.scan_airline_profile.on_order is 'Aircraft on order: the Fleet table''s on order total';
comment on column public.scan_airline_profile.avg_age_years is 'Its fleet''s average age, years (the totals'' Ø age)';
comment on column public.scan_airline_profile.stations is 'Stations (General statistics)';
comment on column public.scan_airline_profile.staff is 'Staff (General statistics)';
comment on column public.scan_airline_profile.passengers is 'Transported passengers, since it was founded (General statistics)';
comment on column public.scan_airline_profile.alliance is 'Its alliance''s name (General Information), null when in none';
comment on column public.scan_airline_profile.parent_game_id is 'Its parent company''s game (enterprise) id (General Information), null when it has none';
comment on column public.scan_airline_profile.founded is 'The day it was founded in the game (General Information)';
comment on column public.scan_airline_profile.read_ok is 'True when the page read; false when it didn''t, with the reason in note (no other figures then)';
comment on column public.scan_airline_profile.note is 'Why the page didn''t read, as the capture or gscan.py sent it';
comment on column public.scan_airline_profile.read_at is 'When the database stored the page';
comment on function private.scan_ingest(bigint, text, jsonb) is 'The world scan''s writes (spec docs/specs/2026-10-21-scan-in-capture.md): ingest_snapshot()''s body, shared by ingest_snapshot() (scripts/scanner/gscan.py, the fallback) and capture_scan() (Capture all airlines), with no check of its own. Kinds: start (a game_scans row in p_world_id, the default world when null; answers snapshot_id; the world''s scans left unfinished more than an hour ago are stopped first), airline (its totals in game_scan_airlines and its schedule in game_scan_schedules, the airline placed in airlines by game ID through private.scan_airline()), airport (its page in game_scan_airports, the airlines stationed there placed too), fleet (since 23 Oct, spec docs/specs/2026-10-23-rival-fleets.md §3: an airline''s overview page, its types in scan_airline_fleet and its totals and general figures in scan_airline_profile, replacing the same scan''s earlier read; a page sent with error, or without a types list, is kept as read_ok false with the reason, and never replaces a page the same scan read; answers {ok, read_ok, rows}), finish (status done and the airport summaries, private.scan_summarise(); a scan that isn''t there is ignored) and markets (the weekly report''s market summaries, replacing the scan''s earlier ones). Every kind but start takes its scan''s own world. An unknown kind, or a scan that isn''t there, raises an error.';
comment on function public.ingest_snapshot(text, text, jsonb) is 'Receives the world scanner''s results (start, airlines, airports, finish) into game_scans, game_scan_airlines, game_scan_schedules and game_scan_airports; finish builds the scan''s airport summaries. Kind markets takes the weekly report''s market summaries for a scan (scan_airline_markets), and since 23 Oct kind fleet an airline''s overview page (scan_airline_fleet, scan_airline_profile; spec docs/specs/2026-10-23-rival-fleets.md). Every airline a scan sees gets an airlines row (change log actor script). Same kinds, payloads and answers as before #13; a start scans the default world. Since 21 Oct the work is private.scan_ingest(), which the evening capture''s scan (capture_scan()) shares; this stays for scripts/scanner/gscan.py, the fallback run by hand. Needs the ingest secret.';
comment on function public.capture_scan(text, text, jsonb) is 'The world scan in Capture all airlines (capture/capture_all.user.js 1.5, 1.8 with the fleet pages; spec docs/specs/2026-10-21-scan-in-capture.md; manual §7), with the capture key: kinds start, airline, airport, fleet (since 23 Oct, spec docs/specs/2026-10-23-rival-fleets.md §2: an airline''s overview page, its fleet by type and its general figures, or its error) and finish, with the payloads scripts/scanner/gscan.py sends ingest_snapshot(), stored exactly as ingest_snapshot() stores them (private.scan_ingest()), in the key''s world. start answers {ok, snapshot_id, carried_on}: an unfinished scan of the world started within the hour (private.scan_open()) is carried on instead of starting another (one start at a time per world); the other kinds answer {ok, snapshot_id} (fleet with read_ok and rows) and take only a scan of the key''s world. A wrong or missing key gets {"ok": false, "error": "bad key"}, an unknown kind {"ok": false, "error": "bad kind"}, and a payload that doesn''t read {"ok": false, "error": ...}, writing nothing. Every airline the scan sees gets an airlines row (change log actor capture, detail capture_scan). Runs as owner with an empty search path.';
comment on function private.scan_fleet(bigint, bigint, bigint) is 'An airline''s fleet in a world scan (since 23 Oct; spec docs/specs/2026-10-23-rival-fleets.md §4), for competition(), with no check of its own: from p_scan_id''s overview page (scan_airline_profile, scan_airline_fleet) overall, on_order, avg_age_years, types_count and types (its 5 biggest by overall, then on order, each with on_order and avg_age_years), and against p_before_id''s overall_before, on_order_before, overall_change and on_order_change (null when that scan didn''t read its page). Null when p_scan_id didn''t read it.';
comment on function private.scan_order_flags(bigint, bigint, bigint, text[]) is 'The world''s rival order books in a world scan (since 23 Oct; spec docs/specs/2026-10-23-rival-fleets.md §4), for competition()''s order_flags, with no check of its own: every airline whose overview page p_scan_id read with aircraft on order, that isn''t one of ours, freighter-only airlines left out (flights in the scan, none of them passenger flights by private.scan_passenger()), flagged starting (on order and no flights in the scan) or orders (on order at least the world''s settings.rival_orders_flag_pct of its fleet and at least rival_orders_flag_min); each with airline_id, name, kind, fleet, on_order, share, weekly, on_order_change and fleet_change (against p_before_id, private.scan_fleet()), on_pairs (a passenger flight on one of p_pairs, ''AAA-BBB'' with the codes in order), at_bases (departures from one of p_airline_id''s hubs or focus cities in scan_airline_airports), meets and words; the biggest share first. The list is the same for every airline; only on_pairs, at_bases and meets depend on it. An empty list with no scan.';
comment on function private.fig_export(bigint, timestamp with time zone) is 'The captured figures (#19): every figure for every airline of a world in one document, for export_for_report(''figures''), with no check of its own. Since 22 Oct each airline also carries competition()''s competitors, self and scans (private.fig_competition() with p_limit 0), for the weekly report''s three biggest competitors (manual §7), and since 23 Oct its order_flags and each competitor''s fleet (spec docs/specs/2026-10-23-rival-fleets.md §5).';

do $describe$
declare x record; d text;
begin
  for x in select * from (values
      ('public.competition(bigint, timestamptz, integer)', ' Fleets (since 23 Oct', ' Fleets (since 23 Oct; spec docs/specs/2026-10-23-rival-fleets.md §4): each competitor and each rival profile has fleet, from its overview page in the latest scan (scan_airline_fleet, scan_airline_profile, through private.scan_fleet()): overall, on_order, avg_age_years, types_count and types (its 5 biggest by overall, each with on_order), and overall_before, on_order_before, overall_change and on_order_change against the week-before scan (null when either scan didn''t read its page); fleet is null when the latest scan didn''t read it. order_flags (private.scan_order_flags()): the same world-wide list in every airline''s answer, every airline in the latest scan that isn''t one of ours, freighter-only airlines left out (private.scan_passenger()), with aircraft on order at least settings.rival_orders_flag_pct of its fleet and at least rival_orders_flag_min (kind orders), or on order and no flights in the scan (kind starting); each with airline_id, name, kind, fleet, on_order, share (percent of its fleet), weekly (its departures a week in the scan), on_order_change and fleet_change against the week-before scan, on_pairs (it flies one of this airline''s city pairs), at_bases (it departs from one of its hubs or focus cities), meets (either) and words; biggest share first. No flag feeds the openings, the contested test or the fare pause.'),
      ('public.export_for_report(text, text, text)', 'rival-fleets.md) kind figures', ' Since 23 Oct (spec docs/specs/2026-10-23-rival-fleets.md) kind figures also gives each airline competition()''s order_flags and each competitor''s fleet, and the scan kinds take fleet (an airline''s overview page) through ingest_snapshot().'),
      ('public.system_status(bigint, timestamptz)', 'fleet_pages and fleet_failed', ' Since 23 Oct (spec docs/specs/2026-10-23-rival-fleets.md §5) scan also has fleet_pages and fleet_failed: the overview pages the latest scan read and failed (scan_airline_profile).')
    ) v(f, mark, more) loop
    d := obj_description(x.f::regprocedure, 'pg_proc');
    if position(x.mark in coalesce(d, '')) = 0 then
      execute format('comment on function %s is %L', x.f, coalesce(d, '') || x.more);
    end if;
  end loop;
end
$describe$;

select set_config('equinox.actor', '', true), set_config('equinox.actor_detail', '', true);

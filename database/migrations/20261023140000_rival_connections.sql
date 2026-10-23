-- Rivals' connecting options on our pairs (23 Oct 2026; spec docs/specs/2026-10-23-rival-connections.md, option A of
-- brief docs/briefs/2026-10-23-rival-connections.md with a 1.5 detour limit; the manual's decided entry "To build:
-- rivals' connecting options").
--
-- Why (Gitesh, 23 Oct): competition() counts a rival on our pair only if it flies it direct, so a rival whose hub sits
-- between two of our cities (Icelandair between Europe and North America) shows as nobody on the pair. Each evening, when
-- the world scan finishes, the database now works out every rival's one-stop connections on our pairs from that scan's
-- schedules; Competition, a route's page and the weekly report show them as "connecting" departures a week beside the
-- direct ones, never added to them. Display only: nothing else reads them.
--
-- Adds two tables, one setting and two internal functions, and replaces seven functions with the same arguments (CREATE
-- OR REPLACE); drops and renames nothing. It works the connections out once for every finished scan that still has its
-- schedules (a few seconds), so Competition has them from the start; it changes no other data.
--   1. public.scan_rival_connections: one row per scan, rival, pair, direction and connecting airport, with its
--      departures a week that connect and the shortest gap (detail: the monthly archive takes it with the scan schedules
--      after a full calendar month). public.scan_rival_connections_week: one row per scan, rival and pair (least,
--      greatest), with each direction's total and both, kept for good. RLS on with no rule and no access for anon or
--      authenticated (manual §1): read through functions only.
--   2. settings rival_connection_detour_max 1.5, in every world, described.
--   3. private.scan_connection_via() (the top 3 connecting airports of a list) and private.scan_connections(scan) (the
--      calculation, also callable by hand for a past scan), both internal.
--   4. private.scan_ingest() kind finish works them out after the airport summaries, and the finish note adds
--      "connections: N rivals on M of our pairs"; a calculation that fails or runs out of time never stops the finish
--      (the note says so, and it can be run by hand).
--   5. The monthly archive (private.archive_tables(), archive_due(), archive_order(), archive_where(), so the manifest,
--      the export and the guarded delete) takes scan_rival_connections by its scan's time, as the scan schedules.
--   6. private.fig_competition() (so competition(), the briefing and the weekly report's figures) gives each market, each
--      opening (with each rival's own), each rival profile and each of the three biggest competitors connecting_weekly
--      and its connecting airports, beside the direct figures; private.fig_route_story() (route_story()) gives each rival
--      on the pair its connecting departures and airports, the rivals that only connect, and each scan's.
-- Market share, threats, openings' order, the contested test, hubs first, the three biggest competitors (still chosen by
-- direct departures) and the fare pause don't read them: nothing else in those functions changes.

select set_config('equinox.actor', 'migration', true),
       set_config('equinox.actor_detail', '20261023140000_rival_connections', true);

-- ============================================================ 1. the tables
create table public.scan_rival_connections (
  scan_id bigint not null,
  world_id bigint not null,
  airline_id bigint not null,
  origin text not null,
  dest text not null,
  via text not null,
  weekly_departures integer not null check (weekly_departures > 0),
  best_gap_min integer not null check (best_gap_min >= 0),
  primary key (scan_id, airline_id, origin, dest, via),
  constraint scan_rival_connections_scan_world_fkey foreign key (scan_id, world_id) references public.game_scans (id, world_id) on delete cascade,
  constraint scan_rival_connections_airline_fkey foreign key (airline_id, world_id) references public.airlines (id, world_id)
);
create index scan_rival_connections_airline_world_idx on public.scan_rival_connections (airline_id, world_id);

create table public.scan_rival_connections_week (
  scan_id bigint not null,
  world_id bigint not null,
  airline_id bigint not null,
  airport_a text not null,
  airport_b text not null,
  weekly_a_to_b integer not null default 0,
  weekly_b_to_a integer not null default 0,
  weekly_departures integer not null,
  vias jsonb not null default '[]'::jsonb,
  primary key (scan_id, airline_id, airport_a, airport_b),
  constraint scan_rival_connections_week_pair_check check (airport_a < airport_b),
  constraint scan_rival_connections_week_scan_world_fkey foreign key (scan_id, world_id) references public.game_scans (id, world_id) on delete cascade,
  constraint scan_rival_connections_week_airline_fkey foreign key (airline_id, world_id) references public.airlines (id, world_id)
);
create index scan_rival_connections_week_airline_world_idx on public.scan_rival_connections_week (airline_id, world_id);

alter table public.scan_rival_connections enable row level security;
alter table public.scan_rival_connections_week enable row level security;
revoke all on table public.scan_rival_connections, public.scan_rival_connections_week from public, anon, authenticated;

-- ============================================================ 2. the setting
insert into public.settings (world_id, airline_id, key, value, unit, description, since, reason)
select w.id, null, 'rival_connection_detour_max', '1.5'::jsonb, 'times the direct distance',
       'Rivals'' connecting options (private.scan_connections(); spec docs/specs/2026-10-23-rival-connections.md §1): a rival''s one-stop connection A→H→B counts on our pair A–B only if the two legs'' great-circle distances together are at most this many times A–B''s (airports.lat and lon), so Gatwick–Paris via New York doesn''t count. 1.25 keeps a real hub on the way (Kolkata–Shanghai via Kunming); 1.5 also lets in some longer doglegs. Display only: shown beside direct departures on Competition, a route''s page and the weekly report, never added to them, and nothing else reads it.',
       date '2026-10-23', 'Gitesh, 23 Oct (brief docs/briefs/2026-10-23-rival-connections.md, option A with 1.5 instead of the recommended 1.25)'
  from public.worlds w
on conflict on constraint settings_world_airline_key_key do nothing;

-- ============================================================ 3. the calculation
-- the top 3 connecting airports of a list of {via, weekly}: each airport's departures added up, biggest first
create or replace function private.scan_connection_via(p jsonb)
 returns jsonb
 language sql
 immutable
 set search_path to ''
as $function$
  select coalesce(jsonb_agg(jsonb_build_object('via', x.via, 'weekly', x.weekly) order by x.weekly desc, x.via), '[]'::jsonb)
    from (select e ->> 'via' as via, sum((e ->> 'weekly')::int)::int as weekly
            from jsonb_array_elements(case when jsonb_typeof(p) = 'array' then p else '[]'::jsonb end) e
           where coalesce(e ->> 'via', '') <> ''
           group by 1 order by 2 desc, 1 limit 3) x
$function$;

-- every rival's one-stop connections on our pairs in one scan, from its schedules (spec
-- docs/specs/2026-10-23-rival-connections.md §1): replaces the scan's rows in both tables and answers what it found.
-- The planner estimates the schedules' rows badly (one row a JSON list), and with nested loops it joins the 200,000-odd
-- pairings to our 6,000-odd pairs one by one (minutes on the 23 Oct scan); hash joins take under a second, so nested
-- loops are off inside this function only.
create or replace function private.scan_connections(p_scan_id bigint)
 returns jsonb
 language plpgsql
 set search_path to ''
 set enable_nestloop to 'off'
as $function$
declare
  t0 timestamptz := clock_timestamp(); w bigint; v_detour numeric; v_wait numeric; v_res jsonb; n_rows int := 0; n_no_coords int := 0;
begin
  select s.world_id into w from public.game_scans s where s.id = p_scan_id;
  if w is null then raise exception 'no such scan: %', coalesce(p_scan_id::text, 'none given') using errcode = '22023'; end if;
  v_detour := private.fig_num(w, null, 'rival_connection_detour_max');
  v_wait := private.fig_num(w, null, 'connection_max_wait_h');
  delete from public.scan_rival_connections where scan_id = p_scan_id;
  delete from public.scan_rival_connections_week where scan_id = p_scan_id;

  with
  -- our pairs: any of our airlines flies (a route with rotations) or has on its list (not removed), either way round
  pr as materialized (
    select distinct least(r.hub_code, r.dest_code) as a, greatest(r.hub_code, r.dest_code) as b
      from public.routes r join public.airlines al on al.id = r.airline_id join public.groups g on g.id = al.group_id
     where r.world_id = w and g.kind = 'ours'
       and (not r.removed or exists (select 1 from public.rotations rt where rt.route_id = r.id))),
  -- every rival's passenger flights in the scan (private.scan_passenger(), our airlines left out), each with its weekdays
  -- as a mask (bit 0 Monday ... bit 6 Sunday), its local departure and arrival in minutes, and the weekdays it arrives on
  -- (the next day when the arrival is earlier than the departure: it crossed midnight)
  fl as materialized (
    select sc.airline_id, e.i as n, f ->> 2 as o, f ->> 3 as d,
           (position('1' in coalesce(f ->> 4, '')) > 0)::int | ((position('2' in coalesce(f ->> 4, '')) > 0)::int << 1)
             | ((position('3' in coalesce(f ->> 4, '')) > 0)::int << 2) | ((position('4' in coalesce(f ->> 4, '')) > 0)::int << 3)
             | ((position('5' in coalesce(f ->> 4, '')) > 0)::int << 4) | ((position('6' in coalesce(f ->> 4, '')) > 0)::int << 5)
             | ((position('7' in coalesce(f ->> 4, '')) > 0)::int << 6) as m,
           split_part(f ->> 5, ':', 1)::int * 60 + split_part(f ->> 5, ':', 2)::int as dep,
           split_part(f ->> 6, ':', 1)::int * 60 + split_part(f ->> 6, ':', 2)::int as arr
      from public.game_scan_schedules sc
      join public.airlines ra on ra.id = sc.airline_id
      left join public.groups g on g.id = ra.group_id
      cross join lateral jsonb_array_elements(case when jsonb_typeof(sc.flights) = 'array' then sc.flights else '[]'::jsonb end) with ordinality e(f, i)
     where sc.scan_id = p_scan_id and coalesce(g.kind, 'rival') <> 'ours' and jsonb_typeof(f) = 'array'
       and private.scan_passenger(f ->> 7) and coalesce(f ->> 2, '') <> '' and coalesce(f ->> 3, '') <> '' and f ->> 2 <> f ->> 3
       and coalesce(f ->> 5, '') ~ '^\d{1,2}:\d{2}$' and coalesce(f ->> 6, '') ~ '^\d{1,2}:\d{2}$'),
  fm as materialized (
    select fl.*, case when fl.arr < fl.dep then ((fl.m << 1) | (fl.m >> 6)) & 127 else fl.m end as am
      from fl where fl.m > 0),
  -- each first flight A→H joined to the same airline's flights H→B (B not A) on a day it arrives, on our pairs; the gap
  -- in local time at H, at most connection_max_wait_h (the minimum connection time below)
  j as materialized (
    select x.airline_id, x.n, x.o, x.d as h, y.d as b, (x.am & y.m) as hit, y.dep - x.arr as gap
      from fm x
      join fm y on y.airline_id = x.airline_id and y.o = x.d
      join pr on pr.a = least(x.o, y.d) and pr.b = greatest(x.o, y.d)
     where y.d <> x.o and (x.am & y.m) <> 0 and y.dep - x.arr between 0 and v_wait * 60),
  ap as materialized (select a.code, radians(a.lat::float8) as la, radians(a.lon::float8) as lo
                        from public.airports a where a.lat is not null and a.lon is not null),
  mc as materialized (select wa.airport_code, wa.mct_min from public.world_airports wa where wa.world_id = w and wa.mct_min is not null),
  -- at least the minimum connection time at H (90 minutes where unknown, as the website's trip search); then the detour,
  -- great-circle (a routing with an airport lacking coordinates is kept aside, to be counted)
  k as (
    select j.*, a.code is not null and h.code is not null and b.code is not null as coords,
           case when a.code is not null and h.code is not null and b.code is not null then
             (2 * asin(least(1, sqrt(power(sin((h.la - a.la) / 2), 2) + cos(a.la) * cos(h.la) * power(sin((h.lo - a.lo) / 2), 2)))))
             + (2 * asin(least(1, sqrt(power(sin((b.la - h.la) / 2), 2) + cos(h.la) * cos(b.la) * power(sin((b.lo - h.lo) / 2), 2)))))
             <= v_detour * (2 * asin(least(1, sqrt(power(sin((b.la - a.la) / 2), 2) + cos(a.la) * cos(b.la) * power(sin((b.lo - a.lo) / 2), 2)))))
           end as near
      from j
      left join mc on mc.airport_code = j.h
      left join ap a on a.code = j.o left join ap h on h.code = j.h left join ap b on b.code = j.b
     where j.gap >= coalesce(mc.mct_min, 90)),
  -- each first flight once a day: the days any of its onward options runs (its departures from A), its shortest gap
  ff as (
    select k.airline_id, k.n, k.o, k.h, k.b, bit_or(k.hit) as hit, min(k.gap) as gap, bool_and(k.coords) as coords
      from k where k.near is not false
     group by 1, 2, 3, 4, 5),
  -- by rival, pair, direction and connecting airport: the departures a week that connect, the shortest gap
  agg as materialized (
    select ff.airline_id, ff.o, ff.b, ff.h, sum(length(replace(ff.hit::bit(7)::text, '0', '')))::int as weekly, min(ff.gap) as gap,
           bool_and(ff.coords) as coords
      from ff group by 1, 2, 3, 4),
  ins as (
    insert into public.scan_rival_connections (scan_id, world_id, airline_id, origin, dest, via, weekly_departures, best_gap_min)
    select p_scan_id, w, agg.airline_id, agg.o, agg.b, agg.h, agg.weekly, agg.gap from agg where agg.coords and agg.weekly > 0
    returning 1)
  select (select count(*) from ins)::int, (select count(*) from agg where not agg.coords)::int into n_rows, n_no_coords;

  insert into public.scan_rival_connections_week (scan_id, world_id, airline_id, airport_a, airport_b, weekly_a_to_b, weekly_b_to_a, weekly_departures, vias)
  select p_scan_id, w, c.airline_id, least(c.origin, c.dest), greatest(c.origin, c.dest),
         coalesce(sum(c.weekly_departures) filter (where c.origin < c.dest), 0)::int,
         coalesce(sum(c.weekly_departures) filter (where c.origin > c.dest), 0)::int,
         sum(c.weekly_departures)::int,
         private.scan_connection_via(jsonb_agg(jsonb_build_object('via', c.via, 'weekly', c.weekly_departures)))
    from public.scan_rival_connections c where c.scan_id = p_scan_id
   group by c.airline_id, least(c.origin, c.dest), greatest(c.origin, c.dest);

  select jsonb_build_object(
           'scan_id', p_scan_id, 'rows', n_rows,
           'rivals', (select count(distinct x.airline_id) from public.scan_rival_connections_week x where x.scan_id = p_scan_id)::int,
           'pairs', (select count(distinct (x.airport_a, x.airport_b)) from public.scan_rival_connections_week x where x.scan_id = p_scan_id)::int,
           'weekly', (select coalesce(sum(x.weekly_departures), 0) from public.scan_rival_connections_week x where x.scan_id = p_scan_id)::int,
           'left_out_no_coordinates', n_no_coords,
           'ms', round(extract(epoch from clock_timestamp() - t0) * 1000)::int)
    into v_res;
  return v_res || jsonb_build_object('words', format('connections: %s rivals on %s of our pairs', v_res ->> 'rivals', v_res ->> 'pairs')
                                              || case when n_no_coords > 0 then format(' (%s routing%s left out: an airport without coordinates)', n_no_coords,
                                                                                         case when n_no_coords = 1 then '' else 's' end) else '' end);
end
$function$;

-- ============================================================ 4. the scan's finish works them out
CREATE OR REPLACE FUNCTION private.scan_ingest(p_world_id bigint, p_kind text, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare v_world bigint; v_scan bigint; v_al bigint; v_res jsonb; n int := 0; v_err text; t jsonb; v_conn jsonb;
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
        -- the rivals' one-stop connections on our pairs, from this scan's schedules (spec
        -- docs/specs/2026-10-23-rival-connections.md §1), after the airport summaries; the finish note says how many. A
        -- calculation that fails, or runs out of time, never stops the finish: the note says so (run it by hand)
        begin
          v_conn := private.scan_connections(v_scan);
          update public.game_scans set note = concat_ws(' · ', nullif(note, ''), v_conn ->> 'words') where id = v_scan;
        exception when query_canceled or others then
          update public.game_scans set note = concat_ws(' · ', nullif(note, ''), 'connections not worked out: ' || left(sqlerrm, 200)) where id = v_scan;
        end;
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

-- ============================================================ 5. the archive: the detail table with the scan schedules
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
    select 'change_log', date_trunc('month', c.changed_at at time zone 'UTC')::date, count(*)
      from public.change_log c, k
     where k.table_name = 'change_log' and c.changed_at < k.kept_from::timestamp at time zone 'UTC'
     group by 2) x
   order by x.month, x.table_name
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
    when 'change_log' then format('(%1$s.changed_at >= %2$s and %1$s.changed_at < %3$s)', a, f, t)
  end;
end
$function$;

-- ============================================================ 6. the figures: competition() and route_story()
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
  v_threats jsonb; v_body jsonb; v_group jsonb; v_flags jsonb; v_conn_scan bigint;
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
  -- the rivals' connections (spec docs/specs/2026-10-23-rival-connections.md §3): the latest scan's, when they were worked
  -- out for it (its row in scan_rival_connections_week, written with the detail); a scan from before them gives none, so
  -- its answer has no connecting figures rather than zeros
  select v_latest into v_conn_scan where v_latest is not null
     and exists (select 1 from public.scan_rival_connections_week c where c.scan_id = v_latest);

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
  -- the rivals' connecting departures a week on the airline's pairs in the latest scan (since 23 Oct, spec
  -- docs/specs/2026-10-23-rival-connections.md §3), both ways, by connecting airport: shown beside direct, never added
  cx as materialized (
    select c.airline_id, coalesce(ra.public_name, ra.game_name, ra.planner_name, 'airline ' || c.airline_id) as name,
           least(c.origin, c.dest) as a, greatest(c.origin, c.dest) as b, c.via, sum(c.weekly_departures)::int as weekly
      from public.scan_rival_connections c
      join public.airlines ra on ra.id = c.airline_id
     where c.scan_id = v_conn_scan
       and least(c.origin, c.dest) || '-' || greatest(c.origin, c.dest) = any (coalesce(v_pairs, '{}'::text[]))
     group by 1, 2, 3, 4, 5),
  -- by pair and rival, by pair (the total, each rival's own and the top 3 airports) and by rival
  cxr as (select cx.a, cx.b, cx.airline_id, cx.name, sum(cx.weekly)::int as weekly,
                 private.scan_connection_via(jsonb_agg(jsonb_build_object('via', cx.via, 'weekly', cx.weekly))) as via
            from cx group by 1, 2, 3, 4),
  cxp as (select r.a, r.b, sum(r.weekly)::int as weekly,
                 jsonb_agg(jsonb_build_object('airline_id', r.airline_id, 'name', r.name, 'weekly', r.weekly, 'via', r.via) order by r.weekly desc, r.name) as rivals,
                 (select private.scan_connection_via(jsonb_agg(jsonb_build_object('via', y.via, 'weekly', y.weekly))) from cx y where y.a = r.a and y.b = r.b) as via
            from cxr r group by 1, 2),
  cxa as (select cx.airline_id, sum(cx.weekly)::int as weekly, count(distinct (cx.a, cx.b))::int as pairs,
                 private.scan_connection_via(jsonb_agg(jsonb_build_object('via', cx.via, 'weekly', cx.weekly))) as via
            from cx group by 1),

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
  -- by market: every rival's connecting departures on its pairs, with the top 3 airports (since 23 Oct)
  mcx as (select mp.market_id, sum(cx.weekly)::int as weekly,
                 private.scan_connection_via(jsonb_agg(jsonb_build_object('via', cx.via, 'weekly', cx.weekly))) as via
            from mp join cx on cx.a = mp.a and cx.b = mp.b group by 1),
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
             -- connecting (since 23 Oct): never part of total or share; absent when the latest scan has none worked out
             || case when v_conn_scan is not null then jsonb_build_object(
                  'connecting_weekly', coalesce((select x.weekly from mcx x where x.market_id is not distinct from ms.market_id), 0),
                  'connecting_via', coalesce((select x.via from mcx x where x.market_id is not distinct from ms.market_id), '[]'::jsonb))
                else '{}'::jsonb end
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
             -- connecting (since 23 Oct): the rivals' one-stop departures on the pair, beside rivals_weekly, never in it
             || case when v_conn_scan is not null then jsonb_build_object(
                  'connecting_weekly', coalesce(oc.weekly, 0), 'connecting_via', coalesce(oc.via, '[]'::jsonb), 'connecting', coalesce(oc.rivals, '[]'::jsonb))
                else '{}'::jsonb end
             -- a thin 1-star city's alternative, only where there is one
             || case when o.alt_type is not null
                     then jsonb_build_object('variant_alt', o.alt_type, 'variant_note', format('or the %s if thin', o.alt_type))
                     else '{}'::jsonb end
             order by o.rank) filter (where o.rank <= v_limit), '[]'::jsonb) as d,
           count(*)::int as n, (count(*) filter (where o.allowed))::int as n_allowed, (count(*) filter (where o.trunk))::int as n_trunks
      from op4 o left join ol l on l.a = o.a and l.b = o.b left join cxp oc on oc.a = o.a and oc.b = o.b),
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
             -- connecting (since 23 Oct): its one-stop departures a week on this airline's pairs, beside weekly_on_pairs, never in it
             || case when v_conn_scan is not null then jsonb_build_object(
                  'connecting_weekly', coalesce((select x.weekly from cxa x where x.airline_id = pf.airline_id), 0),
                  'connecting_pairs', coalesce((select x.pairs from cxa x where x.airline_id = pf.airline_id), 0),
                  'connecting_via', coalesce((select x.via from cxa x where x.airline_id = pf.airline_id), '[]'::jsonb))
                else '{}'::jsonb end
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
             -- connecting (since 23 Oct): its one-stop departures a week on this airline's pairs, beside on_pairs, never in it
             || case when v_conn_scan is not null then jsonb_build_object(
                  'connecting_weekly', coalesce((select x.weekly from cxa x where x.airline_id = cr.airline_id), 0),
                  'connecting_pairs', coalesce((select x.pairs from cxa x where x.airline_id = cr.airline_id), 0),
                  'connecting_via', coalesce((select x.via from cxa x where x.airline_id = cr.airline_id), '[]'::jsonb))
                else '{}'::jsonb end
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
      'fleet (each competitor''s and rival profile''s, since 23 Oct): from its overview page in the latest scan (scan_airline_fleet, scan_airline_profile): overall, on order, average age and its 5 biggest types, with the change in overall and on order against the week-before scan (null when either scan didn''t read its page); null when the latest scan didn''t read it. order_flags: every airline in the latest scan that isn''t one of ours, freighters only left out, with aircraft on order at least rival_orders_flag_pct of its fleet and at least rival_orders_flag_min (kind orders), or on order and no flights in the scan (kind starting); the same list for every airline, each marked on_pairs (it flies one of this airline''s city pairs), at_bases (it departs from one of its hubs or focus cities) and meets (either). No flag feeds the openings, the contested test or the fare pause.',
      'connecting (since 23 Oct): each rival''s one-stop departures a week on the airline''s city pairs in the latest scan (scan_rival_connections, worked out at the scan''s finish by private.scan_connections(): same airline, the second flight from the connecting airport''s minimum connection time to connection_max_wait_h after the first lands, both legs together at most rival_connection_detour_max times the direct distance, each first flight counted once). connecting_weekly on each market, each opening (with each rival''s own in connecting), each rival profile and each competitor (with connecting_pairs), each with its top 3 connecting airports (connecting_via); shown beside direct, never added to it: total, share, rivals_weekly, on_pairs and the three biggest competitors (chosen by direct departures) are direct only, and the openings'' order, the contested test, hubs first, the threats and the fare pause don''t read it. Absent when the latest scan has no connections worked out.'));
end
$function$;

CREATE OR REPLACE FUNCTION private.fig_route_story(p_route_id bigint, p_as_of timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare
  v_today date := (p_as_of at time zone 'UTC')::date;
  w bigint; al bigint; v_code text; v_name text; v_hub text; v_dest text; v_pair text; v_removed boolean;
  v_route jsonb; v_launch date; v_launch_from text; v_latest date; v_from date; v_wfrom date; v_min numeric;
  v_out int := 0; v_back int := 0; v_rotations int := 0; v_types jsonb; v_ladder jsonb; v_fares jsonb;
  v_scan bigint; v_scan_at timestamptz; v_before bigint; v_before_at timestamptz; v_ids bigint[];
  v_days jsonb; v_weeks jsonb; v_changes jsonb; v_other jsonb; v_scanpart jsonb;
begin
  select r.world_id, r.airline_id, r.hub_code, r.dest_code, r.removed,
         jsonb_build_object(
           'id', r.id, 'hub', r.hub_code, 'dest', r.dest_code, 'pair', least(r.hub_code, r.dest_code) || '-' || greatest(r.hub_code, r.dest_code),
           'city', coalesce(r.city_override, r.city), 'stars', coalesce(r.stars_override, r.stars),
           'distance_km', coalesce(r.distance_override_km, r.distance_km), 'removed', r.removed,
           'market', case when mk.id is null then null else jsonb_build_object('id', mk.id, 'name', mk.name, 'layout', mk.layout) end,
           -- the cabin it calls for: its own choice, else its market's (Routes' header, since 21 Oct)
           'cabin', jsonb_build_object('layout', coalesce(nullif(r.cabin_choice, ''), mk.layout), 'own', nullif(r.cabin_choice, '') is not null,
                                       'market_layout', mk.layout))
    into w, al, v_hub, v_dest, v_removed, v_route
    from public.routes r
    left join public.markets mk on mk.id = case when r.market_cleared then null else coalesce(r.market_override_id, r.market_id) end
   where r.id = p_route_id;
  if w is null then raise exception 'no such route: %', coalesce(p_route_id::text, 'none given') using errcode = '22023'; end if;
  v_pair := least(v_hub, v_dest) || '-' || greatest(v_hub, v_dest);
  select a.iata_code, coalesce(a.public_name, a.planner_name, a.game_name) into v_code, v_name from public.airlines a where a.id = al;
  v_min := private.fig_num(w, al, 'competition_threat_min_weekly');

  -- launched: its earliest rotation's launch day, as route profit and the fare ladder find a route's age; else its first
  -- day in the daily history
  select min(rt.launched_on) into v_launch from public.rotations rt where rt.route_id = p_route_id and rt.airline_id = al;
  if v_launch is not null then
    v_launch_from := 'rotation';
  else
    select min(d.day) into v_launch from public.route_days d
     where d.airline_id = al and d.flights > 0 and d.day <= v_today
       and ((d.origin_code = v_hub and d.dest_code = v_dest) or (d.origin_code = v_dest and d.dest_code = v_hub))
       and (d.route_id = p_route_id or d.route_id is null);
    if v_launch is not null then v_launch_from := 'history'; end if;
  end if;
  -- the latest captured day: the airline's latest day in the daily history by the moment
  select max(d.day) into v_latest from public.route_days d where d.airline_id = al and d.day <= v_today;
  -- the days from launch, or the last 90 if longer; the weeks, 13 blocks of 7 days ending on the latest captured day
  v_from := greatest(coalesce(v_launch, v_latest - 89), v_latest - 89);
  v_wfrom := greatest(coalesce(v_launch, v_latest - 90), v_latest - 90);

  -- ---------- now: the live schedule each way, the types flying it, the fare ladder's rows
  select coalesce(sum(cardinality(l.days_utc)) filter (where l.leg_no = 1), 0)::int,
         coalesce(sum(cardinality(l.days_utc)) filter (where l.leg_no = 2), 0)::int, count(distinct rt.id)::int
    into v_out, v_back, v_rotations
    from public.rotations rt join public.flight_legs l on l.rotation_id = rt.id
   where rt.route_id = p_route_id and rt.airline_id = al and not v_removed;
  select coalesce(jsonb_agg(jsonb_build_object('type_id', x.id, 'type', x.name, 'aircraft', x.n) order by x.n desc, x.name), '[]'::jsonb) into v_types
    from (select t.id, t.name, count(distinct a.id)::int as n
            from public.rotations rt join public.flight_legs l on l.rotation_id = rt.id
            join public.aircraft a on a.id = l.aircraft_id join public.aircraft_types t on t.id = a.aircraft_type_id
           where rt.route_id = p_route_id and rt.airline_id = al and not v_removed
           group by t.id, t.name) x;
  v_ladder := private.fig_fare_ladder(al, p_as_of);
  select coalesce(jsonb_agg(e - 'route_id' - 'hub' - 'dest' order by e ->> 'cabin' = 'business'), '[]'::jsonb) into v_fares
    from jsonb_array_elements(v_ladder -> 'routes') e where (e ->> 'route_id')::bigint = p_route_id;

  -- ---------- the days and the weeks, both directions together, from the daily history
  with rd as (
    select d.day, d.flights, d.passengers, d.seats, d.eco_pax, d.eco_seats, d.bus_pax, d.bus_seats, d.eco_fare_avg, d.bus_fare_avg,
           d.revenue, d.costs, d.profit, d.block_min,
           -- the passengers on the flights whose loads were captured (the flights seats counts): by cabin, else (a day
           -- before the cabins were kept) the passengers up to the seats
           case when d.eco_pax is not null or d.bus_pax is not null then coalesce(d.eco_pax, 0) + coalesce(d.bus_pax, 0)
                else least(d.passengers, d.seats) end as lpax,
           (v_latest - d.day) / 7 as wk
      from public.route_days d
     where d.airline_id = al and d.day between v_wfrom and v_latest and d.flights > 0
       and ((d.origin_code = v_hub and d.dest_code = v_dest) or (d.origin_code = v_dest and d.dest_code = v_hub))
       and (d.route_id = p_route_id or d.route_id is null)),
  g as (
    select true as is_day, rd.day as d0, rd.day as d1, count(distinct rd.day)::int as n_days,
           sum(rd.flights) as flights, sum(rd.passengers) as pax, sum(rd.seats) as seats, sum(rd.lpax) as lpax,
           sum(rd.eco_pax) as eco_pax, sum(rd.eco_seats) as eco_seats, sum(rd.bus_pax) as bus_pax, sum(rd.bus_seats) as bus_seats,
           sum(rd.eco_fare_avg * rd.eco_pax) filter (where rd.eco_pax > 0 and rd.eco_fare_avg is not null) as eco_fx,
           sum(rd.eco_pax) filter (where rd.eco_pax > 0 and rd.eco_fare_avg is not null) as eco_fn, avg(rd.eco_fare_avg) as eco_fa,
           sum(rd.bus_fare_avg * rd.bus_pax) filter (where rd.bus_pax > 0 and rd.bus_fare_avg is not null) as bus_fx,
           sum(rd.bus_pax) filter (where rd.bus_pax > 0 and rd.bus_fare_avg is not null) as bus_fn, avg(rd.bus_fare_avg) as bus_fa,
           sum(rd.revenue) as revenue, sum(rd.costs) as costs, sum(rd.profit) as profit, sum(rd.block_min) as block_min
      from rd where rd.day >= v_from group by rd.day
    union all
    select false, v_latest - rd.wk * 7 - 6, v_latest - rd.wk * 7, count(distinct rd.day)::int,
           sum(rd.flights), sum(rd.passengers), sum(rd.seats), sum(rd.lpax),
           sum(rd.eco_pax), sum(rd.eco_seats), sum(rd.bus_pax), sum(rd.bus_seats),
           sum(rd.eco_fare_avg * rd.eco_pax) filter (where rd.eco_pax > 0 and rd.eco_fare_avg is not null),
           sum(rd.eco_pax) filter (where rd.eco_pax > 0 and rd.eco_fare_avg is not null), avg(rd.eco_fare_avg),
           sum(rd.bus_fare_avg * rd.bus_pax) filter (where rd.bus_pax > 0 and rd.bus_fare_avg is not null),
           sum(rd.bus_pax) filter (where rd.bus_pax > 0 and rd.bus_fare_avg is not null), avg(rd.bus_fare_avg),
           sum(rd.revenue), sum(rd.costs), sum(rd.profit), sum(rd.block_min)
      from rd where rd.wk < 13 group by rd.wk),
  f as (
    select g.is_day, g.d0, g.d1,
           jsonb_build_object(
             'flights', g.flights, 'passengers', g.pax, 'seats', g.seats,
             'load_pct', round(100.0 * g.lpax / nullif(g.seats, 0), 1),
             'eco_pax', g.eco_pax, 'eco_seats', g.eco_seats, 'eco_load_pct', round(100.0 * g.eco_pax / nullif(g.eco_seats, 0), 1),
             'bus_pax', g.bus_pax, 'bus_seats', g.bus_seats, 'bus_load_pct', round(100.0 * g.bus_pax / nullif(g.bus_seats, 0), 1),
             'eco_fare', round(coalesce(g.eco_fx / nullif(g.eco_fn, 0), g.eco_fa), 2),
             'bus_fare', round(coalesce(g.bus_fx / nullif(g.bus_fn, 0), g.bus_fa), 2),
             'revenue', round(g.revenue / 1000000, 5), 'costs', round(g.costs / 1000000, 5), 'profit', round(g.profit / 1000000, 5),
             'block_hours', round(g.block_min / 60.0, 2),
             'profit_per_hour', case when g.block_min > 0 then round((g.profit / 1000000) / (g.block_min / 60.0), 5) end)
           || case when g.is_day then jsonb_build_object('day', g.d0)
                   else jsonb_build_object('from', g.d0, 'to', g.d1, 'days', g.n_days) end as o
      from g)
  select coalesce(jsonb_agg(f.o order by f.d0) filter (where f.is_day), '[]'::jsonb),
         coalesce(jsonb_agg(f.o order by f.d0 desc) filter (where not f.is_day), '[]'::jsonb)
    into v_days, v_weeks
    from f;

  -- ---------- events from the change log: the schedule's saves for this route's rotations and legs (each save, its
  -- txid, one event), and the route's own cabin choice. Changes made by a migration (data loads and fixes) aren't events.
  with rots as (
    select rt.id from public.rotations rt where rt.route_id = p_route_id
    union
    select (c.row_key ->> 'id')::bigint from public.change_log c
     where c.table_name = 'rotations' and c.world_id = w and c.op in ('insert', 'delete')
       and (coalesce(c.new_values, c.old_values) ->> 'route_id')::bigint = p_route_id),
  legs as (
    select l.id, l.flight_no from public.flight_legs l where l.rotation_id in (select rots.id from rots)
    union
    select (c.row_key ->> 'id')::bigint, (coalesce(c.new_values, c.old_values) ->> 'flight_no')::int from public.change_log c
     where c.table_name = 'flight_legs' and c.world_id = w and c.op in ('insert', 'delete')
       and (coalesce(c.new_values, c.old_values) ->> 'rotation_id')::bigint in (select rots.id from rots)),
  ch as materialized (
    select c.txid, c.changed_at, c.table_name, c.op, c.old_values, c.new_values, (c.row_key ->> 'id')::bigint as rid,
           (select max(lg.flight_no) from legs lg where lg.id = (c.row_key ->> 'id')::bigint) as fno
      from public.change_log c
     where c.world_id = w and c.changed_at <= p_as_of and coalesce(c.actor, '') <> 'migration'
       and ((c.table_name = 'rotations' and (c.row_key ->> 'id')::bigint in (select rots.id from rots))
         or (c.table_name = 'flight_legs' and (c.row_key ->> 'id')::bigint in (select legs.id from legs)))),
  sv as (
    select ch.txid, min(ch.changed_at) as at,
           bool_or(ch.table_name = 'rotations' and ch.op = 'insert') as added,
           bool_or(ch.table_name = 'rotations' and ch.op = 'delete') as removed,
           bool_or(ch.table_name = 'flight_legs' and ch.op = 'update' and ch.new_values ? 'aircraft_id') as ac,
           bool_or(ch.table_name = 'flight_legs' and ch.op = 'update' and ch.new_values ?| array['dep_utc_min', 'days_utc', 'block_min']) as timed,
           -- the rotations a save adds are the launch itself when each launched on the route's launch day or before
           coalesce(bool_and((ch.new_values ->> 'launched_on')::date <= v_launch) filter (where ch.table_name = 'rotations' and ch.op = 'insert'), false) as at_launch,
           string_agg(distinct ch.fno::text, '/' order by ch.fno::text) filter (where ch.table_name = 'flight_legs' and ch.op = 'insert') as nos_in,
           string_agg(distinct ch.fno::text, '/' order by ch.fno::text) filter (where ch.table_name = 'flight_legs' and ch.op = 'delete') as nos_out,
           min(case when jsonb_typeof(ch.new_values -> 'days_utc') = 'array' then jsonb_array_length(ch.new_values -> 'days_utc') end)
             filter (where ch.table_name = 'flight_legs' and ch.op = 'insert') as days_in,
           min(ch.new_values ->> 'days_utc') filter (where ch.table_name = 'flight_legs' and ch.op = 'insert') as days_in_text,
           string_agg(distinct ch.fno::text, '/' order by ch.fno::text) filter (where ch.table_name = 'flight_legs' and ch.op = 'update' and ch.new_values ? 'aircraft_id') as nos_ac,
           string_agg(distinct coalesce((select a.registration from public.aircraft a where a.id = (ch.new_values ->> 'aircraft_id')::bigint), 'no aircraft'), ', ')
             filter (where ch.table_name = 'flight_legs' and ch.op = 'update' and ch.new_values ? 'aircraft_id') as regs,
           string_agg(
             concat_ws(' ', coalesce(v_code || ' ' || ch.fno, 'a flight'),
                       case when ch.new_values ? 'dep_utc_min' then
                         format('%s → %s UTC', coalesce(to_char(make_interval(mins => (ch.old_values ->> 'dep_utc_min')::int), 'HH24:MI'), '—'),
                                coalesce(to_char(make_interval(mins => (ch.new_values ->> 'dep_utc_min')::int), 'HH24:MI'), '—')) end,
                       case when ch.new_values ? 'days_utc' then
                         format('days %s → %s', coalesce(translate(ch.old_values ->> 'days_utc', '[], ', ''), '—'),
                                coalesce(translate(ch.new_values ->> 'days_utc', '[], ', ''), '—')) end,
                       case when ch.new_values ? 'block_min' then
                         format('block %s → %s', coalesce(to_char(make_interval(mins => (ch.old_values ->> 'block_min')::int), 'FMHH24:MI'), '—'),
                                coalesce(to_char(make_interval(mins => (ch.new_values ->> 'block_min')::int), 'FMHH24:MI'), '—')) end),
             ', ' order by ch.fno, ch.rid)
             filter (where ch.table_name = 'flight_legs' and ch.op = 'update' and ch.new_values ?| array['dep_utc_min', 'days_utc', 'block_min']) as times
      from ch group by ch.txid),
  ev as (
    select (sv.at at time zone 'UTC')::date as day, sv.at,
           case when sv.added then 'frequency added' when sv.removed then 'frequency removed' when sv.ac then 'aircraft changed' else 'retimed' end as kind,
           case when sv.added then format('%s added, %s', coalesce(v_code || ' ' || sv.nos_in, 'a frequency'),
                                          case when sv.days_in = 7 then 'daily' when sv.days_in is not null then 'days ' || translate(sv.days_in_text, '[], ', '') else 'its days not given' end)
                when sv.removed then format('%s removed', coalesce(v_code || ' ' || sv.nos_out, 'a frequency'))
                when sv.ac then format('%s now on %s', coalesce(v_code || ' ' || sv.nos_ac, 'its flights'), sv.regs) || case when sv.timed then ' and retimed: ' || sv.times else '' end
                else sv.times end as words
      from sv
     where (sv.added and not sv.at_launch) or (not sv.added and (sv.removed or sv.ac or sv.timed)))
  select coalesce(jsonb_agg(jsonb_build_object('day', ev.day, 'kind', ev.kind, 'words', ev.words, 'at', private.fig_ts(ev.at))), '[]'::jsonb)
    into v_changes from ev;

  -- the fare plan's rows for the route (fare tests, and the ladder's moves with level_pct), and the route's cabin choice
  select coalesce(jsonb_agg(x.e), '[]'::jsonb) into v_other
    from (select jsonb_build_object(
                   'day', fp.proposed_on, 'kind', 'fare', 'cabin', coalesce(fp.cabin_class, 'economy'), 'level', fp.level_pct,
                   'change_pct', fp.change_pct, 'move', fp.ladder_move, 'dropped', fp.status = 'dropped', 'reason', fp.reason,
                   'words', case when fp.level_pct is not null
                                 then format('%s %s %s%%', coalesce(fp.cabin_class, 'economy'),
                                             case fp.ladder_move when 'up' then 'up to' when 'down' then 'down to' else 'holds at' end, trim_scale(fp.level_pct))
                                 else format('%s %s%s%% fare test', coalesce(fp.cabin_class, 'economy'),
                                             case when coalesce(fp.change_pct, 0) >= 0 then '+' else '−' end, trim_scale(abs(coalesce(fp.change_pct, 0)))) end
                            || case when fp.status = 'dropped' then ', dropped' else '' end) as e
            from public.fare_plan fp
           where fp.route_id = p_route_id and fp.airline_id = al and fp.proposed_on <= v_today
          union all
          select jsonb_build_object(
                   'day', (c.changed_at at time zone 'UTC')::date, 'kind', 'cabin', 'at', private.fig_ts(c.changed_at),
                   'cabin', nullif(c.new_values ->> 'cabin_choice', ''), 'before', nullif(c.old_values ->> 'cabin_choice', ''),
                   'words', case when nullif(c.new_values ->> 'cabin_choice', '') is null
                                 then format('own cabin %s cleared: its market''s from now', coalesce(nullif(c.old_values ->> 'cabin_choice', ''), ''))
                                 else format('cabin set to %s', c.new_values ->> 'cabin_choice')
                                      || case when nullif(c.old_values ->> 'cabin_choice', '') is not null
                                              then format(' (was %s)', c.old_values ->> 'cabin_choice') else '' end end)
            from public.change_log c
           where c.table_name = 'routes' and c.world_id = w and c.op = 'update' and (c.row_key ->> 'id')::bigint = p_route_id
             and c.new_values ? 'cabin_choice' and c.changed_at <= p_as_of and coalesce(c.actor, '') <> 'migration') x;

  -- ---------- the scans: the latest finished by the moment (with its schedules), and the week before as competition()
  -- picks it (the latest at least 6 days older, else the oldest there is)
  select s.id, s.taken_at into v_scan, v_scan_at from public.game_scans s
   where s.world_id = w and s.status = 'done' and s.taken_at <= p_as_of
     and exists (select 1 from public.game_scan_schedules x where x.scan_id = s.id)
   order by s.taken_at desc, s.id desc limit 1;
  if v_scan is not null then
    select s.id, s.taken_at into v_before, v_before_at from public.game_scans s
     where s.world_id = w and s.status = 'done' and s.taken_at <= v_scan_at - interval '6 days'
       and exists (select 1 from public.game_scan_schedules x where x.scan_id = s.id)
     order by s.taken_at desc, s.id desc limit 1;
    if v_before is null then
      select s.id, s.taken_at into v_before, v_before_at from public.game_scans s
       where s.world_id = w and s.status = 'done' and s.taken_at <= p_as_of and s.id <> v_scan
         and exists (select 1 from public.game_scan_schedules x where x.scan_id = s.id)
       order by s.taken_at, s.id limit 1;
    end if;
  end if;
  -- every finished scan by the moment with its schedules, each with the one before it; read: the latest, the week before,
  -- and each scan since launch with the one before it
  with sc as (
    select s.id, s.taken_at, lag(s.id) over o as prev_id
      from public.game_scans s
     where s.world_id = w and s.status = 'done' and s.taken_at <= p_as_of
       and exists (select 1 from public.game_scan_schedules x where x.scan_id = s.id)
    window o as (order by s.taken_at, s.id))
  select array_remove(array_agg(distinct z.id), null) into v_ids
    from (select v_scan as id union all select v_before
          union all select sc.id from sc where v_launch is not null and sc.taken_at >= v_launch::timestamp at time zone 'UTC'
          union all select sc.prev_id from sc where v_launch is not null and sc.taken_at >= v_launch::timestamp at time zone 'UTC') z;

  with sc as (
    select s.id, s.taken_at, lag(s.id) over o as prev_id
      from public.game_scans s
     where s.world_id = w and s.status = 'done' and s.taken_at <= p_as_of
       and exists (select 1 from public.game_scan_schedules x where x.scan_id = s.id)
    window o as (order by s.taken_at, s.id)),
  since as (select sc.* from sc where v_launch is not null and sc.taken_at >= v_launch::timestamp at time zone 'UTC'),
  -- each airline's passenger departures a week on the pair, both ways, in each scan read (private.scan_pair_flights());
  -- every airline that isn't one of ours is a rival (competition analysis's rule)
  ex as materialized (
    select x.scan_id, x.airline_id, sum(x.weekly)::int as weekly, coalesce(g.kind, 'rival') <> 'ours' as rival,
           coalesce(ra.public_name, ra.game_name, ra.planner_name, 'airline ' || x.airline_id) as name
      from private.scan_pair_flights(coalesce(v_ids, '{}'::bigint[]), array[v_pair]) x
      join public.airlines ra on ra.id = x.airline_id
      left join public.groups g on g.id = ra.group_id
     group by x.scan_id, x.airline_id, g.kind, ra.public_name, ra.game_name, ra.planner_name),
  -- a rival that started on the pair (none in the scan before) or added competition_threat_min_weekly a week, between
  -- each pair of consecutive scans since launch (competition_threats()'s rule)
  rv as (
    select s.id, s.taken_at, n.airline_id, n.name, coalesce(p.weekly, 0) as then_w, n.weekly as now_w
      from since s
      join ex n on n.scan_id = s.id and n.rival
      left join ex p on p.scan_id = s.prev_id and p.airline_id = n.airline_id
     where s.prev_id is not null and n.weekly > 0 and (coalesce(p.weekly, 0) = 0 or n.weekly - p.weekly >= v_min)),
  sh as (
    select s.id, s.taken_at,
           coalesce((select sum(e.weekly) from ex e where e.scan_id = s.id and e.airline_id = al), 0)::int as ours,
           coalesce((select sum(e.weekly) from ex e where e.scan_id = s.id and e.rival), 0)::int as rivals
      from since s),
  lt as (
    select e.airline_id, e.name, e.weekly, b.weekly as before_w
      from ex e left join ex b on b.scan_id = v_before and b.airline_id = e.airline_id
     where e.scan_id = v_scan and e.rival),
  tot as (select coalesce(sum(lt.weekly), 0)::int as rivals from lt),
  -- each rival's one-stop departures on the pair at each scan read (since 23 Oct, spec
  -- docs/specs/2026-10-23-rival-connections.md §3), both ways, by connecting airport; shown beside direct, never added.
  -- Only the scans they were worked out for (a row in scan_rival_connections_week)
  cs as (select s.scan_id from (select unnest(coalesce(v_ids, '{}'::bigint[])) as scan_id) s
          where exists (select 1 from public.scan_rival_connections_week c where c.scan_id = s.scan_id)),
  cn as materialized (
    select c.scan_id, c.airline_id, coalesce(ra.public_name, ra.game_name, ra.planner_name, 'airline ' || c.airline_id) as name,
           c.via, sum(c.weekly_departures)::int as weekly
      from public.scan_rival_connections c join public.airlines ra on ra.id = c.airline_id
     where c.scan_id in (select cs.scan_id from cs)
       and least(c.origin, c.dest) = least(v_hub, v_dest) and greatest(c.origin, c.dest) = greatest(v_hub, v_dest)
     group by 1, 2, 3, 4),
  cr as (select cn.scan_id, cn.airline_id, cn.name, sum(cn.weekly)::int as weekly,
                private.scan_connection_via(jsonb_agg(jsonb_build_object('via', cn.via, 'weekly', cn.weekly))) as via
           from cn group by 1, 2, 3),
  bt as (select coalesce(sum(e.weekly) filter (where e.rival), 0)::int as rivals,
                coalesce(sum(e.weekly) filter (where e.airline_id = al), 0)::int as ours
           from ex e where e.scan_id = v_before)
  select jsonb_build_object(
           'events', (select coalesce(jsonb_agg(jsonb_build_object(
                         'day', (rv.taken_at at time zone 'UTC')::date, 'kind', 'rival', 'at', private.fig_ts(rv.taken_at), 'scan_id', rv.id,
                         'rival_id', rv.airline_id, 'rival', rv.name, 'change', case when rv.then_w = 0 then 'started' else 'added' end,
                         'then', rv.then_w, 'now', rv.now_w, 'added', rv.now_w - rv.then_w,
                         'words', case when rv.then_w = 0 then format('%s started here, %s a week', rv.name, rv.now_w)
                                       else format('%s added %s a week (%s → %s)', rv.name, rv.now_w - rv.then_w, rv.then_w, rv.now_w) end)), '[]'::jsonb)
                        from rv),
           'rivals', jsonb_build_object(
             'scan', case when v_scan is null then null else jsonb_build_object('id', v_scan, 'taken_at', private.fig_ts(v_scan_at)) end,
             'week_before', case when v_before is null then null else jsonb_build_object('id', v_before, 'taken_at', private.fig_ts(v_before_at)) end,
             -- ours: the live schedule, both ways (competition()'s); before: the airline's flights in the week-before scan
             'ours', v_out + v_back, 'rivals_weekly', (select tot.rivals from tot),
             'share', case when v_scan is not null then round(100.0 * (v_out + v_back) / nullif(v_out + v_back + (select tot.rivals from tot), 0), 1) end,
             'ours_before', case when v_before is not null then (select bt.ours from bt) end,
             'rivals_before', case when v_before is not null then (select bt.rivals from bt) end,
             'share_before', case when v_before is not null then (select round(100.0 * bt.ours / nullif(bt.ours + bt.rivals, 0), 1) from bt) end,
             'airlines', (select coalesce(jsonb_agg(jsonb_build_object(
                             'airline_id', lt.airline_id, 'name', lt.name, 'weekly', lt.weekly,
                             'weekly_before', case when v_before is not null then coalesce(lt.before_w, 0) end,
                             'change', case when v_before is not null then lt.weekly - coalesce(lt.before_w, 0) end)
                             -- connecting (since 23 Oct): its one-stop departures on the pair in the latest scan, beside weekly
                             || case when exists (select 1 from cs where cs.scan_id = v_scan)
                                     then jsonb_build_object('connecting_weekly', coalesce((select c.weekly from cr c where c.scan_id = v_scan and c.airline_id = lt.airline_id), 0),
                                                             'connecting_via', coalesce((select c.via from cr c where c.scan_id = v_scan and c.airline_id = lt.airline_id), '[]'::jsonb))
                                     else '{}'::jsonb end
                             order by lt.weekly desc, lt.name), '[]'::jsonb) from lt),
             -- our share at each finished scan since launch: the airline's departures in the scan against every rival's
             'shares', (select coalesce(jsonb_agg(jsonb_build_object(
                           'scan_id', sh.id, 'taken_at', private.fig_ts(sh.taken_at), 'ours', sh.ours, 'rivals', sh.rivals,
                           'share', round(100.0 * sh.ours / nullif(sh.ours + sh.rivals, 0), 1)) order by sh.taken_at, sh.id), '[]'::jsonb) from sh))
           -- connecting (since 23 Oct), only when the latest scan has them worked out: the rivals' one-stop departures on
           -- the pair, those with no direct flight that connect (connecting_only), and each rival's at each scan read
           || case when exists (select 1 from cs where cs.scan_id = v_scan) then jsonb_build_object(
                'connecting_weekly', (select coalesce(sum(c.weekly), 0)::int from cr c where c.scan_id = v_scan),
                'connecting_only', (select coalesce(jsonb_agg(jsonb_build_object('airline_id', c.airline_id, 'name', c.name, 'weekly', 0,
                                                                                  'connecting_weekly', c.weekly, 'connecting_via', c.via)
                                                               order by c.weekly desc, c.name), '[]'::jsonb)
                                       from cr c where c.scan_id = v_scan and not exists (select 1 from lt where lt.airline_id = c.airline_id)),
                'connecting_scans', (select coalesce(jsonb_agg(jsonb_build_object(
                                        'scan_id', s.scan_id, 'taken_at', private.fig_ts(gs.taken_at),
                                        'weekly', (select coalesce(sum(c.weekly), 0)::int from cr c where c.scan_id = s.scan_id),
                                        'airlines', (select coalesce(jsonb_agg(jsonb_build_object('airline_id', c.airline_id, 'name', c.name, 'weekly', c.weekly, 'via', c.via)
                                                                               order by c.weekly desc, c.name), '[]'::jsonb) from cr c where c.scan_id = s.scan_id))
                                        order by gs.taken_at, s.scan_id), '[]'::jsonb)
                                       from cs s join public.game_scans gs on gs.id = s.scan_id))
              else '{}'::jsonb end,
           'used', (select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'taken_at', private.fig_ts(s.taken_at)) order by s.taken_at, s.id), '[]'::jsonb)
                      from since s))
    into v_scanpart;

  return jsonb_build_object(
    'route_id', p_route_id, 'as_of', private.fig_ts(p_as_of), 'latest_day', v_latest,
    'route', v_route || jsonb_build_object(
      'airline', jsonb_build_object('id', al, 'code', v_code, 'name', v_name),
      'launched', v_launch, 'launched_from', v_launch_from,
      'launched_days', case when v_launch is not null then v_today - v_launch end),
    'now', jsonb_build_object(
      'departures', jsonb_build_object('out', v_out, 'back', v_back), 'rotations', v_rotations, 'types', v_types,
      'fares', v_fares, 'launch_pct', v_ladder #> '{settings,launch_pct}', 'week_of', v_ladder -> 'week_of'),
    'days', v_days,
    'weeks', v_weeks,
    'events', (select coalesce(jsonb_agg(x.e order by (x.e ->> 'day')::date desc,
                                          array_position(array['rival', 'fare', 'cabin', 'retimed', 'aircraft changed', 'frequency removed',
                                                               'frequency added', 'launched'], x.e ->> 'kind'),
                                          x.e ->> 'at' desc nulls last, x.e ->> 'words'), '[]'::jsonb)
                 from (select jsonb_array_elements(v_changes) as e
                       union all select jsonb_array_elements(v_other)
                       union all select jsonb_array_elements(v_scanpart -> 'events')
                       union all select jsonb_build_object('day', v_launch, 'kind', 'launched',
                                                           'words', case v_launch_from when 'rotation' then 'launched' else 'first flights in the daily history' end)
                                  where v_launch is not null and v_launch <= v_today) x),
    'rivals', v_scanpart -> 'rivals',
    'scans', jsonb_build_object(
      'latest', v_scanpart #> '{rivals,scan}', 'week_before', v_scanpart #> '{rivals,week_before}', 'since_launch', v_scanpart -> 'used'),
    'notes', jsonb_build_array(
      'Both directions together, from the daily history (route_days): a day is a UTC day, and one with no flights is left out. load_pct is the passengers on the flights whose loads were captured over their seats; profit_per_hour is profit (millions of AS$) over block hours (the scheduled block of the flights that have one). Weeks are 7-day blocks ending on latest_day, newest first.',
      'Events: the schedule''s saves from the change log (one per save; changes a migration made left out; the rotations that are the launch itself not repeated), the fare plan''s rows, the route''s own cabin choice, and rivals that started or added competition_threat_min_weekly a week between consecutive scans since launch (passenger flights only).',
      'Rivals are every airline in the scan that isn''t one of ours; ours now are the live schedule both ways, ours in a scan the airline''s flights in it.',
      'Connecting (since 23 Oct): each rival''s one-stop departures a week on the pair, both ways, from scan_rival_connections (same airline, from the connecting airport''s minimum connection time to connection_max_wait_h, both legs together at most rival_connection_detour_max times the direct distance, each first flight once), with its top 3 connecting airports; beside weekly, never added to it, to rivals_weekly or to the share. connecting_only: rivals with no direct flight that connect; connecting_scans: each rival''s at each scan read that has them worked out. Absent when the latest scan has none worked out.'));
end
$function$;

-- ============================================================ 7. who may call them
revoke all on function private.scan_connection_via(jsonb) from public, anon, authenticated, service_role;
revoke all on function private.scan_connections(bigint) from public, anon, authenticated, service_role;

-- ============================================================ 8. descriptions
comment on table public.scan_rival_connections is 'Rivals'' one-stop connections on our city pairs in a world scan (since 23 Oct; spec docs/specs/2026-10-23-rival-connections.md §1, §2): one row per scan, rival, direction (origin to dest) and connecting airport (via), worked out from the scan''s schedules by private.scan_connections() when the scan finishes. A rival''s flight origin→via joined to its own flights via→dest on the same day (the next where the first lands after midnight local), from the connecting airport''s minimum connection time (world_airports.mct_min, 90 minutes where unknown) to connection_max_wait_h after it lands, both legs together at most rival_connection_detour_max times the direct distance; passenger flights only, our airlines left out; kept only for pairs any of our airlines flies or has on its route list, either way round. Detail: the monthly archive exports and deletes it with the scan schedules after a full calendar month (private.archive_tables()). Read by competition() and route_story(). RLS on with no rule: no access for anon or authenticated, read through functions (manual §1).';
comment on column public.scan_rival_connections.airline_id is 'The rival (an airline that isn''t one of ours) whose two flights connect';
comment on column public.scan_rival_connections.origin is 'Where the first flight leaves: one end of our pair';
comment on column public.scan_rival_connections.dest is 'Where the second flight lands: the pair''s other end';
comment on column public.scan_rival_connections.via is 'The connecting airport, where the first flight lands and the second leaves';
comment on column public.scan_rival_connections.weekly_departures is 'Departures a week from origin that connect onward to dest through via: each first flight once on each day any onward flight connects, so the figure sits beside direct departures on the same scale (never added to them)';
comment on column public.scan_rival_connections.best_gap_min is 'The shortest gap at via between landing and the onward departure, minutes (local times at via)';
comment on table public.scan_rival_connections_week is 'Rivals'' connecting departures on our city pairs by scan, kept for good (since 23 Oct; spec docs/specs/2026-10-23-rival-connections.md §2): one row per scan, rival and pair (airport_a, airport_b, the codes in order), each direction''s total and both, and the top 3 connecting airports; written with scan_rival_connections by private.scan_connections(), and its rows mark the scans whose connections were worked out (competition() and route_story() show none for a scan without). The monthly archive leaves it alone. RLS on with no rule: no access for anon or authenticated, read through functions (manual §1).';
comment on column public.scan_rival_connections_week.airline_id is 'The rival whose connections these are';
comment on column public.scan_rival_connections_week.airport_a is 'The pair''s first airport, in code order';
comment on column public.scan_rival_connections_week.airport_b is 'The pair''s second airport, in code order';
comment on column public.scan_rival_connections_week.weekly_a_to_b is 'Connecting departures a week from airport_a to airport_b';
comment on column public.scan_rival_connections_week.weekly_b_to_a is 'Connecting departures a week from airport_b to airport_a';
comment on column public.scan_rival_connections_week.weekly_departures is 'Both directions together';
comment on column public.scan_rival_connections_week.vias is 'The top 3 connecting airports, [{via, weekly}], biggest first';
comment on function private.scan_connection_via(jsonb) is 'The top 3 connecting airports of a list of {via, weekly} (since 23 Oct; spec docs/specs/2026-10-23-rival-connections.md §3): each airport''s departures added up, biggest first, ties by code; an empty list for none. For private.scan_connections(), competition() and route_story().';
comment on function private.scan_connections(bigint) is 'Works out every rival''s one-stop connections on our city pairs in one world scan, from its schedules (since 23 Oct; spec docs/specs/2026-10-23-rival-connections.md §1), replacing the scan''s rows in scan_rival_connections and scan_rival_connections_week. A rival''s passenger flight (private.scan_passenger(); our airlines left out) A→H joined to its own flights H→B, B not A, on a weekday the first runs (the next day when its local arrival is earlier than its departure), the gap in local time at H at least world_airports.mct_min (90 minutes where unknown) and at most settings.connection_max_wait_h; both legs together at most settings.rival_connection_detour_max times A–B, great-circle from airports.lat and lon (a routing with an airport lacking coordinates is left out and counted); kept only for pairs any of our airlines flies (a route with rotations) or has on its list (not removed), either way round. Each first flight counts once a day however many onward flights it meets, its shortest gap kept. Run by private.scan_ingest() kind finish after the airport summaries; also by hand for a past scan (select private.scan_connections(<scan id>)). Answers {scan_id, rows, rivals, pairs, weekly, left_out_no_coordinates, ms, words}. Nested loops are off inside it (the schedules'' row estimates make them very slow). postgres only.';
comment on function private.scan_ingest(bigint, text, jsonb) is 'The world scan''s writes (spec docs/specs/2026-10-21-scan-in-capture.md): ingest_snapshot()''s body, shared by ingest_snapshot() (scripts/scanner/gscan.py, the fallback) and capture_scan() (Capture all airlines), with no check of its own. Kinds: start (a game_scans row in p_world_id, the default world when null; answers snapshot_id; the world''s scans left unfinished more than an hour ago are stopped first), airline (its totals in game_scan_airlines and its schedule in game_scan_schedules, the airline placed in airlines by game ID through private.scan_airline()), airport (its page in game_scan_airports, the airlines stationed there placed too), fleet (since 23 Oct, spec docs/specs/2026-10-23-rival-fleets.md §3: an airline''s overview page, its types in scan_airline_fleet and its totals and general figures in scan_airline_profile, replacing the same scan''s earlier read; a page sent with error, or without a types list, is kept as read_ok false with the reason, and never replaces a page the same scan read; answers {ok, read_ok, rows}), finish (status done and the airport summaries, private.scan_summarise(); since 23 Oct then the rivals'' connections on our pairs, private.scan_connections(), spec docs/specs/2026-10-23-rival-connections.md §1, its note "connections: N rivals on M of our pairs" added to the scan''s note, and a calculation that fails or runs out of time noted without stopping the finish; a scan that isn''t there is ignored) and markets (the weekly report''s market summaries, replacing the scan''s earlier ones). Every kind but start takes its scan''s own world. An unknown kind, or a scan that isn''t there, raises an error.';
comment on function private.archive_tables() is 'The tables the monthly archive may delete from (design §7), what decides a row''s month, and how many full calendar months each keeps: game_flights, game_events, game_scan_schedules, game_scan_airports and (since 23 Oct, spec docs/specs/2026-10-23-rival-connections.md §2) scan_rival_connections one; change_log 12.';
comment on function private.archive_where(date, text, text) is 'A table''s month as a condition on the table under an alias: one rule for the manifest, the export and the delete. game_flights by dep_at in UTC (by the game''s date where dep_at isn''t known, as the daily history counts it), game_events by event_date, the scan tables (game_scan_schedules, game_scan_airports and since 23 Oct scan_rival_connections) by their scan''s time, change_log by changed_at.';

do $describe$
declare x record; d text;
begin
  for x in select * from (values
      ('public.competition(bigint, timestamptz, integer)', ' Connecting (since 23 Oct', ' Connecting (since 23 Oct; spec docs/specs/2026-10-23-rival-connections.md §3): each rival''s one-stop departures a week on the airline''s city pairs in the latest scan, from scan_rival_connections (private.scan_connections(), at the scan''s finish: same airline, from the connecting airport''s minimum connection time to connection_max_wait_h, both legs together at most rival_connection_detour_max times the direct distance, each first flight once). Each market has connecting_weekly and connecting_via (its top 3 connecting airports); each opening connecting_weekly, connecting_via and connecting (each rival''s, with its airports); each rival profile and each competitor connecting_weekly, connecting_pairs and connecting_via. Shown beside direct, never added: total, share, rivals_weekly, on_pairs, the three biggest competitors (still chosen by direct departures), the openings'' order, the contested test, hubs first, the threats and the fare pause are as without them. The fields are absent when the latest scan has no connections worked out.'),
      ('public.route_story(bigint, timestamptz)', ' Connecting (since 23 Oct', ' Connecting (since 23 Oct; spec docs/specs/2026-10-23-rival-connections.md §3): in rivals, each rival on the pair has connecting_weekly and connecting_via (its one-stop departures a week on the pair in the latest scan, both ways, and its top 3 connecting airports), beside weekly and never added to it, rivals_weekly or the share; rivals also has connecting_weekly (every rival''s), connecting_only (the rivals with no direct flight that connect) and connecting_scans (each rival''s connecting departures and airports at each scan read that has them worked out). Absent when the latest scan has none worked out.'),
      ('public.export_for_report(text, text, text)', 'rival-connections.md) kind figures', ' Since 23 Oct (spec docs/specs/2026-10-23-rival-connections.md) kind figures also gives each competitor its connecting departures on the airline''s pairs (connecting_weekly, connecting_pairs, connecting_via), beside direct and never added to it.'),
      ('private.fig_export(bigint, timestamptz)', 'rival-connections.md', ' Since 23 Oct each competitor also has its connecting departures on the airline''s pairs (connecting_weekly, connecting_pairs, connecting_via; spec docs/specs/2026-10-23-rival-connections.md §4), never added to on_pairs.')
    ) v(f, mark, more) loop
    d := obj_description(x.f::regprocedure, 'pg_proc');
    if position(x.mark in coalesce(d, '')) = 0 then
      execute format('comment on function %s is %L', x.f, coalesce(d, '') || x.more);
    end if;
  end loop;
end
$describe$;

-- ============================================================ 9. the scans there are
-- every finished scan that still has its schedules gets its connections now (a second or so each), so Competition and
-- the route page have them from the first evening; a scan the archive has emptied has none to work out
do $backfill$
declare s record; r jsonb;
begin
  for s in select x.id from public.game_scans x where x.status = 'done'
              and exists (select 1 from public.game_scan_schedules y where y.scan_id = x.id) order by x.taken_at, x.id loop
    r := private.scan_connections(s.id);
    raise notice 'scan %: %, % ms', s.id, r ->> 'words', r ->> 'ms';
  end loop;
end
$backfill$;

select set_config('equinox.actor', '', true), set_config('equinox.actor_detail', '', true);

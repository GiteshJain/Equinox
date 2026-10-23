-- Each week's rivals by pair, kept for good (23 Oct 2026; spec docs/specs/2026-10-23-rival-pairs-history.md, option C of
-- brief docs/briefs/2026-10-23-rival-pairs-history.md; the manual's decided entry "To build: each week's rivals by pair,
-- kept for good").
--
-- Why (Gitesh, 23 Oct): the monthly archive deletes the world scans' full schedules once they are more than a full
-- calendar month old (manual §7), and the route page's "Rivals on the pair" (route_story()) reads those schedules, so
-- from 1 December its line would reach back only one to two months. From the week's kept scan (the first finished scan of
-- the world on or after each Saturday, UTC date) each airline's departures a week on every pair in the world are now kept
-- for good, and route_story() reads them for a scan whose schedules have gone: every evening's scan for the last month,
-- weekly points before.
--
-- Adds one table and two internal functions, and replaces two functions with the same arguments (CREATE OR REPLACE);
-- drops and renames nothing. It fills the table back once from every finished scan still holding its schedules, one a
-- week by the same rule (on live, 23 Oct: scans 3 and 4, about 6,500 rows, well under a second); it changes no other data.
--   1. public.scan_pair_airlines: one row per kept scan, airline and pair it flies (a < b), with its departures a week
--      each way and whether they are passenger flights; every airline in the world, ours included (for our share).
--      Kept for good: the monthly archive leaves it alone (private.archive_tables() doesn't list it, so neither
--      archive_due() nor the guarded delete touches it). RLS on with no rule and no access for anon or authenticated
--      (manual §1): read through functions only.
--   2. private.scan_pairs_keep(scan): writes a finished scan's rows when it is its week's kept scan (none kept yet for
--      that week in its world), else nothing. private.scan_pairs_fill_back(): every finished scan still holding its
--      schedules, one a week (the first by its time), for the weeks with none kept; run once below.
--   3. private.scan_ingest() kind finish keeps the week's pairs after the connections (the capture's and gscan.py's
--      finish alike); a write that fails never stops the finish (the note says so). The note is otherwise unchanged.
--   4. private.fig_route_story() (route_story()): a scan counts when it has its schedules or its kept rows; one whose
--      schedules have gone is read from its kept rows (passenger rows only, as now), the same figures, and marked weekly
--      (shares, since_launch and the scan refs), with weekly_points and daily_from on rivals. Connections stay on the
--      scans that still have their schedules. Nothing else in it changes.

select set_config('equinox.actor', 'migration', true),
       set_config('equinox.actor_detail', '20261023160000_rival_pairs_history', true);

-- ============================================================ 1. the table
create table public.scan_pair_airlines (
  scan_id bigint not null,
  world_id bigint not null,
  airline_id bigint not null,
  a text not null,
  b text not null,
  weekly_a_to_b integer not null default 0 check (weekly_a_to_b >= 0),
  weekly_b_to_a integer not null default 0 check (weekly_b_to_a >= 0),
  passenger boolean not null,
  primary key (scan_id, airline_id, a, b, passenger),
  constraint scan_pair_airlines_pair_check check (a < b),
  constraint scan_pair_airlines_some_check check (weekly_a_to_b + weekly_b_to_a > 0),
  constraint scan_pair_airlines_scan_world_fkey foreign key (scan_id, world_id) references public.game_scans (id, world_id) on delete cascade,
  constraint scan_pair_airlines_airline_fkey foreign key (airline_id, world_id) references public.airlines (id, world_id)
);
-- route_story() reads one pair across the weekly scans; the airline key for its foreign key
create index scan_pair_airlines_pair_idx on public.scan_pair_airlines (a, b, scan_id);
create index scan_pair_airlines_airline_world_idx on public.scan_pair_airlines (airline_id, world_id);

alter table public.scan_pair_airlines enable row level security;
revoke all on table public.scan_pair_airlines from public, anon, authenticated;

-- ============================================================ 2. writing the week's kept scan
-- the week a scan belongs to: the Saturday on or before its UTC date
create or replace function private.scan_week(p_at timestamptz)
 returns date
 language sql
 immutable
 set search_path to ''
as $function$
  select (p_at at time zone 'UTC')::date - ((extract(isodow from (p_at at time zone 'UTC'))::int + 1) % 7)
$function$;

create or replace function private.scan_pairs_keep(p_scan_id bigint)
 returns jsonb
 language plpgsql
 set search_path to ''
as $function$
declare v_world bigint; v_at timestamptz; v_status text; v_week date; v_kept bigint; n int := 0;
begin
  select s.world_id, s.taken_at, s.status into v_world, v_at, v_status from public.game_scans s where s.id = p_scan_id;
  if v_world is null then return jsonb_build_object('scan_id', p_scan_id, 'kept', false, 'rows', 0, 'why', 'no such scan'); end if;
  v_week := private.scan_week(v_at);
  if v_status <> 'done' then
    return jsonb_build_object('scan_id', p_scan_id, 'week', v_week, 'kept', false, 'rows', 0, 'why', 'not finished');
  end if;
  -- the week's kept scan, if there is one already (this scan itself included: a finish sent twice writes once)
  select g.id into v_kept from public.game_scans g
   where g.world_id = v_world and g.taken_at >= (v_week::timestamp at time zone 'UTC') and g.taken_at < ((v_week + 7)::timestamp at time zone 'UTC')
     and exists (select 1 from public.scan_pair_airlines k where k.scan_id = g.id)
   order by g.taken_at, g.id limit 1;
  if v_kept is not null then
    return jsonb_build_object('scan_id', p_scan_id, 'week', v_week, 'kept', false, 'rows', 0, 'kept_scan', v_kept,
                              'why', case when v_kept = p_scan_id then 'already kept' else 'the week has a kept scan' end);
  end if;
  if not exists (select 1 from public.game_scan_schedules x where x.scan_id = p_scan_id) then
    return jsonb_build_object('scan_id', p_scan_id, 'week', v_week, 'kept', false, 'rows', 0, 'why', 'no schedules');
  end if;
  -- each airline's departures a week on each pair, each way: each flight's days counted as gscan.py counts n_weekly
  -- (private.scan_pair_flights()'s rule), passenger and freighter flights apart (private.scan_passenger())
  insert into public.scan_pair_airlines (scan_id, world_id, airline_id, a, b, weekly_a_to_b, weekly_b_to_a, passenger)
  select x.scan_id, x.world_id, x.airline_id, x.a, x.b,
         coalesce(sum(x.n) filter (where x.o = x.a), 0)::int, coalesce(sum(x.n) filter (where x.o = x.b), 0)::int, x.passenger
    from (select sc.scan_id, sc.world_id, sc.airline_id, f ->> 2 as o, least(f ->> 2, f ->> 3) as a, greatest(f ->> 2, f ->> 3) as b,
                 private.scan_passenger(f ->> 7) as passenger, length(regexp_replace(coalesce(f ->> 4, ''), '[^1-7]', '', 'g')) as n
            from public.game_scan_schedules sc
            cross join lateral jsonb_array_elements(case when jsonb_typeof(sc.flights) = 'array' then sc.flights else '[]'::jsonb end) f
           where sc.scan_id = p_scan_id and jsonb_typeof(f) = 'array'
             and coalesce(f ->> 2, '') <> '' and coalesce(f ->> 3, '') <> '' and f ->> 2 <> f ->> 3) x
   group by x.scan_id, x.world_id, x.airline_id, x.a, x.b, x.passenger
  having sum(x.n) > 0;
  get diagnostics n = row_count;
  return jsonb_build_object('scan_id', p_scan_id, 'week', v_week, 'kept', n > 0, 'rows', n);
end
$function$;

create or replace function private.scan_pairs_fill_back()
 returns jsonb
 language plpgsql
 set search_path to ''
as $function$
declare s record; r jsonb; v_res jsonb := '[]'::jsonb;
begin
  -- every finished scan still holding its schedules, in order of time; scan_pairs_keep() keeps the first of each week
  -- that has none kept yet, and writes nothing for the rest
  for s in select g.id from public.game_scans g
            where g.status = 'done' and exists (select 1 from public.game_scan_schedules y where y.scan_id = g.id)
            order by g.world_id, g.taken_at, g.id loop
    r := private.scan_pairs_keep(s.id);
    if (r ->> 'kept')::boolean then v_res := v_res || jsonb_build_array(r); end if;
  end loop;
  return v_res;
end
$function$;

-- ============================================================ 3. the scan's finish keeps the week's pairs
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
        -- each airline's departures on every pair, kept for good when this is the week's kept scan (the first finished on
        -- or after the Saturday; spec docs/specs/2026-10-23-rival-pairs-history.md §2). A second scan the same week writes
        -- nothing. A write that fails never stops the finish: the note says so (run it by hand)
        begin
          perform private.scan_pairs_keep(v_scan);
        exception when query_canceled or others then
          update public.game_scans set note = concat_ws(' · ', nullif(note, ''), 'pairs not kept: ' || left(sqlerrm, 200)) where id = v_scan;
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

-- ============================================================ 4. route_story(): the kept rows where the schedules went
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

  -- ---------- the scans: the latest finished by the moment (with its schedules, or since 23 Oct its kept rows), and the
  -- week before as competition() picks it (the latest at least 6 days older, else the oldest there is)
  select s.id, s.taken_at into v_scan, v_scan_at from public.game_scans s
   where s.world_id = w and s.status = 'done' and s.taken_at <= p_as_of
     and (exists (select 1 from public.game_scan_schedules x where x.scan_id = s.id) or exists (select 1 from public.scan_pair_airlines x where x.scan_id = s.id))
   order by s.taken_at desc, s.id desc limit 1;
  if v_scan is not null then
    select s.id, s.taken_at into v_before, v_before_at from public.game_scans s
     where s.world_id = w and s.status = 'done' and s.taken_at <= v_scan_at - interval '6 days'
       and (exists (select 1 from public.game_scan_schedules x where x.scan_id = s.id) or exists (select 1 from public.scan_pair_airlines x where x.scan_id = s.id))
     order by s.taken_at desc, s.id desc limit 1;
    if v_before is null then
      select s.id, s.taken_at into v_before, v_before_at from public.game_scans s
       where s.world_id = w and s.status = 'done' and s.taken_at <= p_as_of and s.id <> v_scan
         and (exists (select 1 from public.game_scan_schedules x where x.scan_id = s.id) or exists (select 1 from public.scan_pair_airlines x where x.scan_id = s.id))
       order by s.taken_at, s.id limit 1;
    end if;
  end if;
  -- every finished scan by the moment with its schedules or its kept rows (scan_pair_airlines, since 23 Oct: the week's
  -- kept scan once the monthly archive has taken its schedules), each with the one before it; read: the latest, the week
  -- before, and each scan since launch with the one before it
  with sc as (
    select s.id, s.taken_at, lag(s.id) over o as prev_id
      from public.game_scans s
     where s.world_id = w and s.status = 'done' and s.taken_at <= p_as_of
       and (exists (select 1 from public.game_scan_schedules x where x.scan_id = s.id) or exists (select 1 from public.scan_pair_airlines x where x.scan_id = s.id))
    window o as (order by s.taken_at, s.id))
  select array_remove(array_agg(distinct z.id), null) into v_ids
    from (select v_scan as id union all select v_before
          union all select sc.id from sc where v_launch is not null and sc.taken_at >= v_launch::timestamp at time zone 'UTC'
          union all select sc.prev_id from sc where v_launch is not null and sc.taken_at >= v_launch::timestamp at time zone 'UTC') z;

  with sc as (
    select s.id, s.taken_at, lag(s.id) over o as prev_id
      from public.game_scans s
     where s.world_id = w and s.status = 'done' and s.taken_at <= p_as_of
       and (exists (select 1 from public.game_scan_schedules x where x.scan_id = s.id) or exists (select 1 from public.scan_pair_airlines x where x.scan_id = s.id))
    window o as (order by s.taken_at, s.id)),
  since as (select sc.* from sc where v_launch is not null and sc.taken_at >= v_launch::timestamp at time zone 'UTC'),
  -- each airline's passenger departures a week on the pair, both ways, in each scan read: from its schedules where it
  -- still has them (private.scan_pair_flights()), otherwise from its kept rows (scan_pair_airlines, passenger rows only;
  -- spec docs/specs/2026-10-23-rival-pairs-history.md §3), the same figures; every airline that isn't one of ours is a
  -- rival (competition analysis's rule)
  fl as (
    select f.scan_id, f.airline_id, f.weekly from private.scan_pair_flights(coalesce(v_ids, '{}'::bigint[]), array[v_pair]) f
    union all
    select k.scan_id, k.airline_id, k.weekly_a_to_b + k.weekly_b_to_a
      from public.scan_pair_airlines k
     where k.scan_id = any (coalesce(v_ids, '{}'::bigint[])) and k.a = least(v_hub, v_dest) and k.b = greatest(v_hub, v_dest) and k.passenger
       and not exists (select 1 from public.game_scan_schedules y where y.scan_id = k.scan_id)),
  -- the scans read from their kept rows (weekly points)
  wk as (select s.scan_id from (select unnest(coalesce(v_ids, '{}'::bigint[])) as scan_id) s
          where not exists (select 1 from public.game_scan_schedules y where y.scan_id = s.scan_id)),
  ex as materialized (
    select x.scan_id, x.airline_id, sum(x.weekly)::int as weekly, coalesce(g.kind, 'rival') <> 'ours' as rival,
           coalesce(ra.public_name, ra.game_name, ra.planner_name, 'airline ' || x.airline_id) as name
      from fl x
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
          where exists (select 1 from public.scan_rival_connections_week c where c.scan_id = s.scan_id)
            and not exists (select 1 from wk where wk.scan_id = s.scan_id)),
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
             'scan', case when v_scan is null then null else jsonb_build_object('id', v_scan, 'taken_at', private.fig_ts(v_scan_at))
                                                                 || case when v_scan in (select wk.scan_id from wk) then jsonb_build_object('weekly', true) else '{}'::jsonb end end,
             'week_before', case when v_before is null then null else jsonb_build_object('id', v_before, 'taken_at', private.fig_ts(v_before_at))
                                                                     || case when v_before in (select wk.scan_id from wk) then jsonb_build_object('weekly', true) else '{}'::jsonb end end,
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
             -- (since 23 Oct) weekly: the point is a week's kept scan read from its kept rows, its schedules archived
             'shares', (select coalesce(jsonb_agg(jsonb_build_object(
                           'scan_id', sh.id, 'taken_at', private.fig_ts(sh.taken_at), 'ours', sh.ours, 'rivals', sh.rivals,
                           'share', round(100.0 * sh.ours / nullif(sh.ours + sh.rivals, 0), 1),
                           'weekly', exists (select 1 from wk where wk.scan_id = sh.id)) order by sh.taken_at, sh.id), '[]'::jsonb) from sh),
             'weekly_points', (select count(*)::int from sh where exists (select 1 from wk where wk.scan_id = sh.id)),
             'daily_from', case when exists (select 1 from sh join wk on wk.scan_id = sh.id)
                                then (select private.fig_ts(min(sh.taken_at)) from sh where not exists (select 1 from wk where wk.scan_id = sh.id)) end)
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
           'used', (select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'taken_at', private.fig_ts(s.taken_at),
                                                                 'weekly', exists (select 1 from wk where wk.scan_id = s.id)) order by s.taken_at, s.id), '[]'::jsonb)
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
      'Connecting (since 23 Oct): each rival''s one-stop departures a week on the pair, both ways, from scan_rival_connections (same airline, from the connecting airport''s minimum connection time to connection_max_wait_h, both legs together at most rival_connection_detour_max times the direct distance, each first flight once), with its top 3 connecting airports; beside weekly, never added to it, to rivals_weekly or to the share. connecting_only: rivals with no direct flight that connect; connecting_scans: each rival''s at each scan read that has them worked out. Absent when the latest scan has none worked out.',
      'Weekly points (since 23 Oct): a scan whose schedules the monthly archive has taken is read from its kept rows (scan_pair_airlines: the week''s kept scan, the first finished on or after each Saturday, every airline''s departures on every pair, kept for good), the same figures; such a point has weekly true in shares, since_launch and the scans. weekly_points counts them and daily_from is the first point read from full schedules (null when every point is). Before the last month the line is weekly; connections only on scans with their schedules.'));
end
$function$;

-- ============================================================ 5. who may call them
revoke all on function private.scan_week(timestamptz) from public, anon, authenticated, service_role;
revoke all on function private.scan_pairs_keep(bigint) from public, anon, authenticated, service_role;
revoke all on function private.scan_pairs_fill_back() from public, anon, authenticated, service_role;

-- ============================================================ 6. descriptions
comment on table public.scan_pair_airlines is 'Each airline''s departures a week on every city pair in the world, from the week''s kept world scan, kept for good (since 23 Oct; spec docs/specs/2026-10-23-rival-pairs-history.md §1, §2): the first finished scan of the world on or after each Saturday (UTC date), written by private.scan_pairs_keep() at the scan''s finish, and filled back once from the scans still holding their schedules. One row per kept scan, airline (ours included, for our share), pair (a, b, the codes in order) and kind (passenger or not). So a route''s rivals reach back past the monthly archive: route_story() reads it for a scan whose schedules have gone (weekly points). The monthly archive leaves it alone. RLS on with no rule: no access for anon or authenticated, read through functions (manual §1).';
comment on column public.scan_pair_airlines.scan_id is 'The week''s kept scan (game_scans)';
comment on column public.scan_pair_airlines.world_id is 'The scan''s world';
comment on column public.scan_pair_airlines.airline_id is 'The airline flying the pair in the scan, any airline of the world, ours included';
comment on column public.scan_pair_airlines.a is 'The pair''s first airport, in code order';
comment on column public.scan_pair_airlines.b is 'The pair''s second airport, in code order';
comment on column public.scan_pair_airlines.weekly_a_to_b is 'Departures a week from a to b in the scan''s schedule (each flight''s days counted, as gscan.py counts n_weekly)';
comment on column public.scan_pair_airlines.weekly_b_to_a is 'Departures a week from b to a';
comment on column public.scan_pair_airlines.passenger is 'True for passenger flights, false for freighters (private.scan_passenger()); route_story() reads the passenger rows, as it reads the schedules';
comment on function private.scan_week(timestamptz) is 'The week a world scan belongs to (since 23 Oct; spec docs/specs/2026-10-23-rival-pairs-history.md §2): the Saturday on or before its time''s UTC date. For private.scan_pairs_keep().';
comment on function private.scan_pairs_keep(bigint) is 'Keeps a finished world scan''s pairs for good when it is its week''s kept scan (since 23 Oct; spec docs/specs/2026-10-23-rival-pairs-history.md §1, §2): if no scan of the same world in the same week (Saturday to Friday, UTC, private.scan_week()) has rows in scan_pair_airlines yet, writes each airline''s departures a week on every pair from the scan''s schedules (both ways, passenger and freighter apart), else nothing (a second scan the same week, or the same finish twice). A scan not finished, or without its schedules, writes nothing. Run by private.scan_ingest() kind finish after the connections; also by hand. Answers {scan_id, week, kept, rows} and why when nothing was written. postgres only.';
comment on function private.scan_pairs_fill_back() is 'Fills scan_pair_airlines back from the scans still holding their schedules (since 23 Oct; spec docs/specs/2026-10-23-rival-pairs-history.md §2): every finished scan in order of time, through private.scan_pairs_keep(), so each week with none kept gets its first. Run once by the migration 20261023160000_rival_pairs_history; safe to run again (writes nothing for a week already kept). Answers the scans it kept, each {scan_id, week, kept, rows}. postgres only.';
comment on function private.scan_ingest(bigint, text, jsonb) is 'The world scan''s writes (spec docs/specs/2026-10-21-scan-in-capture.md): ingest_snapshot()''s body, shared by ingest_snapshot() (scripts/scanner/gscan.py, the fallback) and capture_scan() (Capture all airlines), with no check of its own. Kinds: start (a game_scans row in p_world_id, the default world when null; answers snapshot_id; the world''s scans left unfinished more than an hour ago are stopped first), airline (its totals in game_scan_airlines and its schedule in game_scan_schedules, the airline placed in airlines by game ID through private.scan_airline()), airport (its page in game_scan_airports, the airlines stationed there placed too), fleet (since 23 Oct, spec docs/specs/2026-10-23-rival-fleets.md §3: an airline''s overview page, its types in scan_airline_fleet and its totals and general figures in scan_airline_profile, replacing the same scan''s earlier read; a page sent with error, or without a types list, is kept as read_ok false with the reason, and never replaces a page the same scan read; answers {ok, read_ok, rows}), finish (status done and the airport summaries, private.scan_summarise(); since 23 Oct then the rivals'' connections on our pairs, private.scan_connections(), spec docs/specs/2026-10-23-rival-connections.md §1, its note "connections: N rivals on M of our pairs" added to the scan''s note, and a calculation that fails or runs out of time noted without stopping the finish; since 23 Oct then the week''s pairs kept for good when it is the week''s kept scan, private.scan_pairs_keep(), spec docs/specs/2026-10-23-rival-pairs-history.md §2, a write that fails noted as "pairs not kept" without stopping the finish; a scan that isn''t there is ignored) and markets (the weekly report''s market summaries, replacing the scan''s earlier ones). Every kind but start takes its scan''s own world. An unknown kind, or a scan that isn''t there, raises an error.';

do $describe$
declare x record; d text;
begin
  for x in select * from (values
      ('public.route_story(bigint, timestamptz)', ' Weekly points (since 23 Oct', ' Weekly points (since 23 Oct; spec docs/specs/2026-10-23-rival-pairs-history.md §3): a scan whose schedules the monthly archive has taken is read from scan_pair_airlines (the week''s kept scan, kept for good; passenger rows), the same figures, and marked weekly true in rivals.shares, scans.since_launch and the scan refs; rivals.weekly_points counts them and rivals.daily_from is the first point read from full schedules. Connections only on the scans with their schedules.')
    ) v(f, mark, more) loop
    d := obj_description(x.f::regprocedure, 'pg_proc');
    if position(x.mark in coalesce(d, '')) = 0 then
      execute format('comment on function %s is %L', x.f, coalesce(d, '') || x.more);
    end if;
  end loop;
end
$describe$;

-- ============================================================ 7. the scans there are
-- every finished scan still holding its schedules, one a week (the first by its time): on live, 23 Oct, scans 3 (week of
-- 3 Oct) and 4 (week of 17 Oct; 5, 7 and 8 are the same week)
do $fill$
declare r jsonb;
begin
  r := private.scan_pairs_fill_back();
  raise notice 'scan pairs kept: %', r;
end
$fill$;

select set_config('equinox.actor', '', true), set_config('equinox.actor_detail', '', true);

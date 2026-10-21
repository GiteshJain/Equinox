-- Flights linked to their routes and aircraft, and the business fare index from the daily history (22 Oct 2026; spec
-- docs/specs/2026-10-21-links-and-business-index.md).
--
-- Why (Gitesh, 21 Oct: "let's build the three loose ends"): two loose ends the route page build turned up.
--   1. Most captured flights had no route or aircraft attached: private.fill_flight_links() ran once, at the 10 Oct data
--      load (20261010120000_planner_data_load.sql), and nothing called it again. The figures match flights by their
--      airports, so nothing was wrong on screen; the links make them sturdier and let a route's history follow it.
--   2. The fare ladder's business index read only game_flights, so it would be lost once a month's flights are archived;
--      economy falls back on the daily history (route_days.eco_fare_avg). Since 22 Oct route_days keeps bus_fare_avg too.
--
-- Replaces functions with the same arguments and fills two columns; adds, drops and renames nothing, so it can be applied
-- from the chat:
--   1. private.fill_flight_links(world): the matching as it was (the schedule's leg with that number and direction, else
--      the airline's route on the airports, that way round first, else the other way; the aircraft by registration), with
--      one fix: when the airports match two routes (one each way round), one that isn't removed comes first. It still
--      touches only flights without a link.
--   2. private.merge_flight(): a flight whose money came before its loads takes the loads row's route, or none until the
--      links are filled right after the matching, so it is linked by its flight number (the schedule's leg) and not by
--      the airports its money-only row was linked by. Its aircraft is kept as before.
--   3. private.capture_page(): after a statement or loads page (after the matching), fill_flight_links() for the world.
--   4. private.capture_refresh(): the same after its matching, with how many in its answer (links).
--   5. private.take_snapshot(): fill_flight_links() before private.history_flows(), so each route day it writes has its
--      route (route_days.route_id is the day's flights' route); how many in its answer (links).
--   6. private.fig_fare_ladder(): the fare index's daily-history step (hd) reads business as it reads economy, from
--      route_days.bus_fare_avg on a day with business passengers (bus_pax > 0), so a business baseline day older than
--      game_flights still has a fare. Nothing else in the ladder changes.
--   7. Filled back now (data only): game_flights' route and aircraft for every flight still without them, then
--      route_days.route_id for every route day still without one, from the airline's route on its airports, either way
--      round, one that isn't removed first. A notice gives the counts, the time and what is left without and why.
-- No index: fill_flight_links() reads only the flights still without a link, and database/tests/flight_links_test.sql
-- times it on the copy (with nothing to link, and with one loads page's flights to link) and prints its plan.

select set_config('equinox.actor', 'migration', true),
       set_config('equinox.actor_detail', '20261022030000_flight_links', true);

-- ============================================================ 1. the links: a live route before a removed one when the airports match two
CREATE OR REPLACE FUNCTION private.fill_flight_links(p_world_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare v_routes int; v_aircraft int;
begin
  -- only the flights still without a link (since 22 Oct each capture page and the daily snapshot call this, so it must
  -- stay cheap): the route by the schedule's leg with that number and direction, else the airline's route on its
  -- airports, either way round: one that isn't removed first (since 22 Oct; before, a removed route that way round won
  -- over a live one the other way), then the one that way round
  update public.game_flights f
     set route_id = coalesce(
           (select r.route_id from public.flight_legs l join public.rotations r on r.id = l.rotation_id
             where l.airline_id = f.airline_id and l.flight_no = f.flight_no and l.origin_code = f.origin_code
               and l.dest_code = f.dest_code
             order by r.id limit 1),
           (select r.id from public.routes r
             where r.airline_id = f.airline_id
               and ((r.hub_code, r.dest_code) = (f.origin_code, f.dest_code) or (r.hub_code, r.dest_code) = (f.dest_code, f.origin_code))
             order by r.removed, r.hub_code <> f.origin_code, r.id limit 1))
   where f.world_id = p_world_id and f.route_id is null and f.origin_code is not null and f.dest_code is not null
     and exists (select 1 from public.routes r where r.airline_id = f.airline_id
                    and ((r.hub_code, r.dest_code) = (f.origin_code, f.dest_code) or (r.hub_code, r.dest_code) = (f.dest_code, f.origin_code)));
  get diagnostics v_routes = row_count;
  -- the aircraft by the registration the loads page or the statement names
  update public.game_flights f set aircraft_id = a.id
    from public.aircraft a
   where f.world_id = p_world_id and f.aircraft_id is null and a.world_id = f.world_id
     and a.registration = coalesce(f.registration, f.maint_registration);
  get diagnostics v_aircraft = row_count;
  return jsonb_build_object('routes', v_routes, 'aircraft', v_aircraft);
end
$function$
;

-- ============================================================ 2. a joined flight is linked by its flight number
CREATE OR REPLACE FUNCTION private.merge_flight(p_money_id bigint, p_loads_id bigint)
 RETURNS boolean
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare l public.game_flights;
begin
  perform 1 from public.game_flights where id = p_money_id and flight_no is null and posted_at is not null for update;
  if not found then return false; end if;
  delete from public.game_flights where id = p_loads_id and posted_at is null and flight_no is not null returning * into l;
  if not found then return false; end if;
  -- the route the loads row had (by its flight number), else none: the capture fills the links right after matching
  -- (private.fill_flight_links()), so a flight whose money came first is linked by its number, not by the airports its
  -- money-only row was linked by (since 22 Oct)
  update public.game_flights
     set game_date = l.game_date, flight_no = l.flight_no, origin_code = l.origin_code, dest_code = l.dest_code,
         dep_local = l.dep_local, arr_local = l.arr_local, dep_at = l.dep_at, arr_at = l.arr_at,
         route_id = l.route_id, aircraft_id = coalesce(aircraft_id, l.aircraft_id),
         registration = l.registration, status = l.status,
         eco_pax = l.eco_pax, eco_seats = l.eco_seats, eco_fare = l.eco_fare, eco_pct = l.eco_pct,
         bus_pax = l.bus_pax, bus_seats = l.bus_seats, bus_fare = l.bus_fare, bus_pct = l.bus_pct,
         fst_pax = l.fst_pax, fst_seats = l.fst_seats, fst_fare = l.fst_fare, fst_pct = l.fst_pct,
         cargo_units = l.cargo_units, cargo_cap = l.cargo_cap, cargo_rate = l.cargo_rate, cargo_pct = l.cargo_pct,
         loads_captured_at = l.loads_captured_at
   where id = p_money_id;
  return true;
end
$function$
;

-- ============================================================ 3. the links after each statement and loads page
CREATE OR REPLACE FUNCTION private.capture_page(p_raw_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  r record; row_ jsonb; c text[]; n int := 0; cur_date date; d text; tsv timestamptz; amt numeric; v_side text;
  v_descr text; dt date; ep int; es int; bp int; bs int; fp int; fs int; cu int; cc int;
  last_ts timestamptz := null; blkn int := 0; maint_pending boolean := false; seen jsonb := '{}'::jsonb; k text; o int; b int;
  v_at timestamptz; v_today date; yr int; v_minutes timestamptz[] := '{}'; v_off int; v_code text; v_dep text;
  v_arr text; t record; v_day date;
begin
  select * into r from public.game_capture_raw where id = p_raw_id;
  if not found then return '{"ok": false}'::jsonb; end if;
  v_at := r.captured_at;
  v_today := (v_at at time zone 'UTC')::date;
  yr := extract(year from (v_at at time zone 'UTC'))::int;

  if r.kind = 'statement' then
    for row_ in select * from jsonb_array_elements(r.rows) loop
      c := array(select x from jsonb_array_elements_text(row_) x where x <> '');
      if array_length(c, 1) < 3 or c[1] !~ '^\d{2}\.\d{2}\. \d{2}:\d{2}' then continue; end if;
      d := substr(c[1], 1, 6); v_descr := c[2];
      tsv := make_timestamptz(yr, substr(d, 4, 2)::int, substr(d, 1, 2)::int, substr(c[1], 8, 2)::int, substr(c[1], 11, 2)::int, 0, 'UTC');
      if tsv > v_at + interval '2 days' then tsv := tsv - interval '1 year'; end if;
      amt := public.as_num(c[3]); v_side := case when c[3] ~ 'C\s*$' then 'C' else 'D' end;
      if amt is null then continue; end if;
      -- blocks: the lines of one flight, when several flights post in the same minute (as since 8 Oct)
      if last_ts is distinct from tsv then last_ts := tsv; blkn := 0; maint_pending := false; end if;
      if v_descr like 'Maintenance of%' then blkn := blkn + 1; maint_pending := true; b := blkn;
      elsif v_descr = 'Passenger transport income' then
        if maint_pending then maint_pending := false; else blkn := blkn + 1; end if; b := blkn;
      elsif v_descr ilike 'Leasing rate%' or v_descr ilike 'Week-end closing%' then b := 0;
      else b := greatest(blkn, 1); end if;
      k := tsv::text || '|' || v_descr || '|' || amt::text; o := coalesce((seen ->> k)::int, 0) + 1;
      seen := seen || jsonb_build_object(k, o);
      insert into public.game_statement (world_id, airline_id, airline, ts, descr, amount, side, route, pax, occ, blk, captured_at)
      values (r.world_id, r.airline_id, r.airline, tsv, v_descr, amt, v_side, substring(v_descr from '\(([A-Z]{3}-[A-Z]{3})\)'),
              (substring(v_descr from 'of (\d+) passengers'))::int, o, b, v_at)
      on conflict on constraint game_statement_pkey do update set blk = excluded.blk;
      n := n + 1;
      v_minutes := v_minutes || tsv;
    end loop;
    perform private.fold_statement(r.airline_id, array(select distinct x from unnest(v_minutes) x));
    perform private.match_flights(r.airline_id);
    -- each captured flight still without them gets its route and aircraft (since 22 Oct)
    perform private.fill_flight_links(r.world_id);

  elsif r.kind = 'events' then
    select private.airport_offset_min(a.world_id, a.home_airport_code) into v_off from public.airlines a where a.id = r.airline_id;
    for row_ in select * from jsonb_array_elements(r.rows) loop
      c := array(select x from jsonb_array_elements_text(row_) x where x <> '');
      if c[1] ~ '^\w+, \d{2}\.\d{2}\.' then
        d := substring(c[1] from '(\d{2}\.\d{2})\.'); cur_date := make_date(yr, substr(d, 4, 2)::int, substr(d, 1, 2)::int);
        if cur_date < v_today - 200 then cur_date := cur_date + interval '1 year'; end if;
        c := c[2:];
      end if;
      if cur_date is null or array_length(c, 1) < 2 or c[1] !~ '^\d{2}:\d{2}$' then continue; end if;
      insert into public.game_events (world_id, airline_id, airline, event_date, event_time, descr, credit, debit, balance,
                                      captured_at, due_at)
      values (r.world_id, r.airline_id, r.airline, cur_date, c[1], c[2], public.as_num(c[3]), public.as_num(c[4]),
              public.as_num(c[5]), v_at, private.local_to_utc(cur_date, c[1], v_off))
      on conflict do nothing;
      n := n + 1;
    end loop;
    perform private.fill_due_at(r.airline_id);

  elsif r.kind = 'loads' then
    -- Load monitoring row: code, tail, origin, "07.10. 04:10 LT", destination, "07.10. 05:23 LT", eco fare,
    -- "156 / 156 (100%)", bus fare, bus, first fare, first, cargo rate, "27 / 32 (84%)", status, details
    for row_ in select * from jsonb_array_elements(r.rows) loop
      c := array(select jsonb_array_elements_text(row_));
      if array_length(c, 1) < 15 or c[1] !~ '^[A-Z0-9]{2,3}\s?\d{1,5}' or c[4] !~ '\d{2}\.\d{2}\. \d{2}:\d{2}' then continue; end if;
      d := substring(c[4] from '(\d{2}\.\d{2})\.'); dt := make_date(yr, substr(d, 4, 2)::int, substr(d, 1, 2)::int);
      if dt > v_today + 2 then dt := dt - interval '1 year'; end if;
      ep := (substring(c[8] from '^\s*(\d+)'))::int; es := (substring(c[8] from '/\s*(\d+)'))::int;
      bp := (substring(c[10] from '^\s*(\d+)'))::int; bs := (substring(c[10] from '/\s*(\d+)'))::int;
      fp := (substring(c[12] from '^\s*(\d+)'))::int; fs := (substring(c[12] from '/\s*(\d+)'))::int;
      cu := (substring(c[14] from '^\s*(\d+)'))::int; cc := (substring(c[14] from '/\s*(\d+)'))::int;
      v_code := regexp_replace(c[1], '\s+', ' ');
      v_dep := substring(c[4] from '(\d{2}:\d{2})'); v_arr := substring(c[6] from '(\d{2}:\d{2})');
      select * into t from private.loads_times(r.world_id, dt, v_dep, v_arr, c[3], c[5]);
      insert into public.game_flights as f (world_id, airline_id, game_date, flight_no, origin_code, dest_code, dep_local,
             arr_local, dep_at, arr_at, registration, status, eco_pax, eco_seats, eco_fare, eco_pct, bus_pax, bus_seats,
             bus_fare, bus_pct, fst_pax, fst_seats, fst_fare, fst_pct, cargo_units, cargo_cap, cargo_rate, cargo_pct,
             loads_captured_at)
      values (r.world_id, r.airline_id, dt, (substring(v_code from '^[A-Z0-9]{2,3}\s?(\d{1,5})'))::int, c[3], c[5], v_dep,
              v_arr, t.dep_at, t.arr_at, c[2], c[15],
              ep, es, public.as_num(c[7]), public.as_num(substring(c[8] from '\((\d+)%\)')),
              bp, bs, public.as_num(c[9]), public.as_num(substring(c[10] from '\((\d+)%\)')),
              fp, fs, public.as_num(c[11]), public.as_num(substring(c[12] from '\((\d+)%\)')),
              cu, cc, public.as_num(c[13]), public.as_num(substring(c[14] from '\((\d+)%\)')), v_at)
      on conflict (airline_id, game_date, flight_no, dep_local) where flight_no is not null do update set
        origin_code = excluded.origin_code, dest_code = excluded.dest_code, arr_local = excluded.arr_local,
        dep_at = coalesce(excluded.dep_at, f.dep_at), arr_at = coalesce(excluded.arr_at, f.arr_at),
        registration = excluded.registration, status = excluded.status,
        eco_pax = excluded.eco_pax, eco_seats = excluded.eco_seats, eco_fare = excluded.eco_fare, eco_pct = excluded.eco_pct,
        bus_pax = excluded.bus_pax, bus_seats = excluded.bus_seats, bus_fare = excluded.bus_fare, bus_pct = excluded.bus_pct,
        fst_pax = excluded.fst_pax, fst_seats = excluded.fst_seats, fst_fare = excluded.fst_fare, fst_pct = excluded.fst_pct,
        cargo_units = excluded.cargo_units, cargo_cap = excluded.cargo_cap, cargo_rate = excluded.cargo_rate,
        cargo_pct = excluded.cargo_pct, loads_captured_at = excluded.loads_captured_at;
      n := n + 1;
    end loop;
    perform private.fill_flight_times(r.airline_id);
    perform private.match_flights(r.airline_id);
    perform private.fill_flight_links(r.world_id);

  elsif r.kind = 'pnl' then
    v_day := private.capture_day(r.world_id, v_at);
    for row_ in select * from jsonb_array_elements(r.rows) loop
      c := array(select jsonb_array_elements_text(row_));
      if array_length(c, 1) < 3 or c[2] !~ 'AS\$' then continue; end if;
      -- the figures and their time from the same capture: the latest
      insert into public.game_pnl as x (world_id, airline_id, airline, captured_on, capture_day, line, current_p, last_p, total_p, captured_at)
      values (r.world_id, r.airline_id, r.airline, v_today, v_day, c[1], public.as_num(c[2]), public.as_num(c[3]),
              public.as_num(c[array_length(c, 1)]), v_at)
      on conflict (airline, captured_on, line) do update set current_p = excluded.current_p, last_p = excluded.last_p,
        total_p = excluded.total_p, capture_day = excluded.capture_day, captured_at = excluded.captured_at
      where excluded.captured_at >= x.captured_at;
      n := n + 1;
    end loop;

  elsif r.kind = 'balance' then
    v_day := private.capture_day(r.world_id, v_at);
    for row_ in select * from jsonb_array_elements(r.rows) loop
      c := array(select jsonb_array_elements_text(row_));
      -- the figures and their time from the same capture: the latest
      if array_length(c, 1) >= 3 and c[1] ~ '^\d{3,4}$' then
        insert into public.game_balance as x (world_id, airline_id, airline, captured_on, capture_day, account, amount, captured_at)
        values (r.world_id, r.airline_id, r.airline, v_today, v_day, c[1] || ' ' || c[2], public.as_num(c[3]), v_at)
        on conflict (airline, captured_on, account) do update set amount = excluded.amount, capture_day = excluded.capture_day,
          captured_at = excluded.captured_at
        where excluded.captured_at >= x.captured_at;
        n := n + 1;
      end if;
      if array_length(c, 1) >= 6 and c[4] ~ '^\d{3,4}$' then
        insert into public.game_balance as x (world_id, airline_id, airline, captured_on, capture_day, account, amount, captured_at)
        values (r.world_id, r.airline_id, r.airline, v_today, v_day, c[4] || ' ' || c[5], public.as_num(c[6]), v_at)
        on conflict (airline, captured_on, account) do update set amount = excluded.amount, capture_day = excluded.capture_day,
          captured_at = excluded.captured_at
        where excluded.captured_at >= x.captured_at;
        n := n + 1;
      end if;
    end loop;
  end if;
  return jsonb_build_object('ok', true, 'kind', r.kind, 'rows', n);
end
$function$
;

-- ============================================================ 4. the links after a refreshs matching
CREATE OR REPLACE FUNCTION private.capture_refresh(p_world_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare a record; v_times int := 0; v_due int := 0; v_matched int := 0; v_links jsonb;
begin
  for a in select al.id from public.airlines al join public.groups g on g.id = al.group_id and g.world_id = al.world_id
            where al.world_id = p_world_id and g.kind = 'ours' order by al.id loop
    v_times := v_times + private.fill_flight_times(a.id);
    v_due := v_due + private.fill_due_at(a.id);
    v_matched := v_matched + private.match_flights(a.id);
  end loop;
  -- then each captured flight still without them gets its route and aircraft (since 22 Oct)
  v_links := private.fill_flight_links(p_world_id);
  return jsonb_build_object('times', v_times, 'due_at', v_due, 'matched', v_matched, 'links', v_links);
end
$function$
;

-- ============================================================ 5. the links before the daily snapshots flows
CREATE OR REPLACE FUNCTION private.take_snapshot(p_world_id bigint, p_day date, p_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_source text DEFAULT 'capture'::text, p_flows boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare v_at timestamptz := coalesce(p_at, now()); v_complete boolean; n int; v_flows jsonb; v_links jsonb;
begin
  if p_source is null or p_source not in ('capture', 'fallback', 'backfill') then
    raise exception 'take_snapshot: source must be capture, fallback or backfill, not %', coalesce(p_source, 'null');
  end if;
  v_complete := private.capture_day_complete(p_world_id, p_day);
  insert into public.airline_days as x (world_id, airline_id, day, complete, source, taken_at, aircraft_by_type,
         aircraft_total, on_order, weekly_departures, weekly_seats, destinations, cash, fixed_next7, cash_at)
  select p_world_id, a.id, p_day, v_complete, p_source, v_at, coalesce(f.aircraft_by_type, '{}'::jsonb),
         coalesce(f.aircraft_total, 0), coalesce(f.on_order, 0), coalesce(s.weekly_departures, 0),
         coalesce(s.weekly_seats, 0), coalesce(s.destinations, 0), c.cash, c.fixed_next7, c.cash_at
    from public.airlines a
    join public.groups g on g.id = a.group_id and g.world_id = a.world_id
    left join private.history_fleet(p_world_id, v_at) f on f.airline_id = a.id
    left join private.history_schedule(p_world_id, p_day) s on s.airline_id = a.id
    left join private.history_cash(p_world_id, p_day, v_at) c on c.airline_id = a.id
   where a.world_id = p_world_id and a.active and g.kind = 'ours' and (a.founded_on is null or a.founded_on <= p_day)
  on conflict (airline_id, day) do update set
    complete = excluded.complete, source = excluded.source, taken_at = excluded.taken_at,
    aircraft_by_type = excluded.aircraft_by_type, aircraft_total = excluded.aircraft_total, on_order = excluded.on_order,
    weekly_departures = excluded.weekly_departures, weekly_seats = excluded.weekly_seats,
    destinations = excluded.destinations, cash = excluded.cash, fixed_next7 = excluded.fixed_next7, cash_at = excluded.cash_at
  where x.source <> 'capture' or excluded.source = 'capture';
  get diagnostics n = row_count;
  -- the flows, once each captured flight still without them has its route and aircraft, so each route day written has
  -- its route (since 22 Oct)
  if p_flows then
    v_links := private.fill_flight_links(p_world_id);
    v_flows := private.history_flows(p_world_id, p_day - 2, p_day);
  end if;
  return jsonb_build_object('day', p_day, 'source', p_source, 'complete', v_complete, 'at', v_at, 'airlines', n)
         || coalesce(v_flows, '{}'::jsonb)
         || case when v_links is null then '{}'::jsonb else jsonb_build_object('links', v_links) end;
end
$function$
;

-- ============================================================ 6. the business fare index from the daily history
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
  v_step numeric; v_up numeric; v_down numeric; v_min numeric; v_hold numeric; v_cap numeric; v_launch numeric; v_floor numeric;
  v_new_days numeric; v_added_days numeric;
  -- every route was at its launch level on 21 Oct 2026 (Gitesh; manual §5): each route's fare that day is its baseline
  v_base_day constant date := date '2026-10-21';
  v_scan bigint; v_scan_at timestamptz;
  v_rows jsonb; v_actions jsonb := '[]'::jsonb; v_n int := 0;
  v_r record; v_sets jsonb; v_change jsonb; v_dir jsonb; v_lv numeric; v_words text;
begin
  v_step := private.fig_num(w, p_airline_id, 'fare_ladder_step_pts');
  v_up := private.fig_num(w, p_airline_id, 'fare_ladder_up_share');
  v_down := private.fig_num(w, p_airline_id, 'fare_ladder_down_share');
  v_min := private.fig_num(w, p_airline_id, 'fare_ladder_min_departures');
  v_hold := private.fig_num(w, p_airline_id, 'fare_ladder_hold_weeks');
  v_cap := private.fig_num(w, p_airline_id, 'fare_ladder_cap_pts');
  v_launch := private.fig_num(w, p_airline_id, 'fare_launch_pct');
  v_new_days := private.fig_num(w, p_airline_id, 'growth_new_route_days');
  v_added_days := private.fig_num(w, p_airline_id, 'fare_ladder_capacity_hold_days');
  select (r.value #>> '{}')::numeric into v_floor from public.world_rules r where r.world_id = w and r.key = 'fare_floor_pct';
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
  -- airline's list has it, either way round (as route profit matches them: route_id is often empty)
  lf as materialized (
    select coalesce(r1.id, r2.id) as route_id, x.*
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
    select lf.route_id, 'economy'::text as cabin, lf.o, lf.game_date, lf.dep_at, lf.eco_pct as pct, lf.eco_fare as fare from lf where lf.eco_pct is not null
    union all
    select lf.route_id, 'business', lf.o, lf.game_date, lf.dep_at, lf.bus_pct, lf.bus_fare from lf where lf.bus_pct is not null and coalesce(lf.bus_seats, 0) > 0),
  -- the 7 days before the moment, by scheduled departure (the departure date where it isn't known)
  st as (select lc.route_id, lc.cabin, count(*)::int as n, (count(*) filter (where lc.pct >= 100))::int as sold, avg(lc.fare) as fare
           from lc
          where coalesce(lc.dep_at, lc.game_date::timestamp at time zone 'UTC') >= p_as_of - interval '7 days'
            and coalesce(lc.dep_at, lc.game_date::timestamp at time zone 'UTC') < p_as_of
          group by lc.route_id, lc.cabin),
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
  bs as (select base.route_id, base.cabin, avg(base.fare) as fare, max(base.day) as day from base group by 1, 2),
  -- the latest captured day by cabin: its average fare, and each flight's fare against its direction's baseline
  lday as (select lc.route_id, lc.cabin, max(lc.game_date) as day from lc where lc.fare > 0 group by 1, 2),
  latest as (select ld.route_id, ld.cabin, ld.day, avg(lc.fare) as fare,
                    array_agg(lc.fare / b.fare order by lc.o, lc.dep_at) filter (where b.fare > 0) as ratios
               from lday ld
               join lc on lc.route_id = ld.route_id and lc.cabin = ld.cabin and lc.game_date = ld.day and lc.fare > 0
               left join base b on b.route_id = lc.route_id and b.cabin = lc.cabin and b.o = lc.o
              group by ld.route_id, ld.cabin, ld.day),
  -- the levels the fare plan recorded (manual §5): before this Saturday, the latest is the level; since it, this week's move
  rec as (select fp.id, fp.route_id, coalesce(fp.cabin_class, 'economy') as cabin, fp.level_pct, fp.ladder_move, fp.proposed_on, fp.reason
            from public.fare_plan fp
           where fp.airline_id = p_airline_id and fp.world_id = w and fp.level_pct is not null and fp.status <> 'dropped'
             and fp.proposed_on <= v_today),
  prev as (select distinct on (r.route_id, r.cabin) r.* from rec r where r.proposed_on < v_week order by r.route_id, r.cabin, r.proposed_on desc, r.id desc),
  wk as (select distinct on (r.route_id, r.cabin) r.* from rec r where r.proposed_on >= v_week order by r.route_id, r.cabin, r.proposed_on desc, r.id desc),
  dn as (select r.route_id, r.cabin, max(r.proposed_on) as down_on from rec r where r.ladder_move = 'down' and r.proposed_on < v_week group by 1, 2),
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
  -- seats; any with flights captured in the 7 days or a move recorded this week
  rc as (select distinct x.route_id, x.cabin
           from (select f.route_id, 'economy'::text as cabin from fq f where f.live
                 union all select bz.route_id, 'business' from biz bz
                 union all select st.route_id, st.cabin from st
                 union all select wk.route_id, wk.cabin from wk) x
           join ro on ro.id = x.route_id),
  lv as (select rc.route_id, rc.cabin, ro.hub_code as hub, ro.dest_code as dest,
                coalesce(st.n, 0) as n, coalesce(st.sold, 0) as sold, st.fare as fare_week,
                lt.fare as latest_fare, lt.day as latest_on, lt.ratios, bs.fare as baseline_fare, bs.day as baseline_on,
                coalesce(pv.level_pct, v_launch) as level, pv.id is not null as recorded,
                wk.id as plan_id, wk.level_pct as plan_level, wk.ladder_move as plan_move, wk.reason as plan_reason,
                coalesce(se.applied, false) as applied, se.seen_on, dn.down_on, ag.first_day, ad.last_day,
                exists (select 1 from contested c where c.a = least(ro.hub_code, ro.dest_code) and c.b = greatest(ro.hub_code, ro.dest_code)) as contested,
                th.rival as rv_name, th.kind as rv_kind, th.added_weekly as rv_added, th.scan_at as rv_on, th.until as rv_until
           from rc join ro on ro.id = rc.route_id
           left join thr th on th.a = least(ro.hub_code, ro.dest_code) and th.b = greatest(ro.hub_code, ro.dest_code)
           left join st on st.route_id = rc.route_id and st.cabin = rc.cabin
           left join latest lt on lt.route_id = rc.route_id and lt.cabin = rc.cabin
           left join bs on bs.route_id = rc.route_id and bs.cabin = rc.cabin
           left join prev pv on pv.route_id = rc.route_id and pv.cabin = rc.cabin
           left join wk on wk.route_id = rc.route_id and wk.cabin = rc.cabin
           left join seen se on se.id = wk.id
           left join dn on dn.route_id = rc.route_id and dn.cabin = rc.cabin
           left join age ag on ag.route_id = rc.route_id
           left join added ad on ad.route_id = rc.route_id),
  mv as (select lv.*,
                case when lv.n > 0 then lv.sold * 100.0 / lv.n end as share,
                v_launch + v_cap as cap_pct,
                -- never under launch, nor under the house floor where another player flies the pair
                greatest(v_launch, case when lv.contested then v_floor end) as floor_pct,
                coalesce(lv.first_day is not null and v_today - lv.first_day < v_new_days, false) as young,
                coalesce(lv.down_on is not null and v_week - lv.down_on < v_hold * 7, false) as held,
                -- a flight added in the last fare_ladder_capacity_hold_days, to a route older than that (manual §5, since 21 Oct)
                coalesce(lv.last_day is not null and v_today - lv.last_day < v_added_days
                         and lv.first_day is not null and v_today - lv.first_day >= v_added_days, false) as added
           from lv),
  dc as (select mv.*,
                case when mv.plan_id is not null then 'planned'
                     when mv.young then 'young'
                     when mv.n < v_min then 'few'
                     when mv.held then 'held'
                     when mv.added then 'added'
                     when mv.rv_name is not null then 'rival'
                     when mv.share >= v_up then case when mv.level >= mv.cap_pct then 'capped' else 'up' end
                     when mv.share >= v_down then 'hold'
                     when mv.level <= mv.floor_pct then 'floor'
                     else 'down' end as k
           from mv),
  fin as (select dc.*,
                 case dc.k when 'planned' then dc.plan_move when 'up' then 'up' when 'down' then 'down' else 'hold' end as move,
                 case dc.k when 'planned' then dc.plan_level
                           when 'up' then least(dc.level + v_step, dc.cap_pct)
                           when 'down' then greatest(dc.level - v_step, dc.floor_pct)
                           else dc.level end as new_level,
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
                   else format('sold out %s of %s, at %s', fin.sold, fin.n, fin.floor_words) end as reason,
                 -- the level the game should show: this week's, once the captures see it
                 case when fin.plan_id is not null and fin.applied then fin.new_level else fin.level end as expect
            from fin),
  -- the fare index: each flight of the latest captured day against its direction's baseline, times the launch level; the
  -- day's average, and the flight furthest from the level the game should show
  ix as (select od.*,
                (select round(avg(r) * v_launch, 1) from unnest(od.ratios) r) as fare_index,
                (select r * v_launch from unnest(od.ratios) r order by abs(r * v_launch - od.expect) desc limit 1) as worst
           from od),
  fx as (select ix.*,
                case when ix.worst is not null then abs(ix.worst - ix.expect) <= 1 end as matches,
                -- set back (manual §5, since 21 Oct): off its level, not on the fare plan this week, not new, and captured
                -- since its newest rotation launched
                coalesce(ix.worst is not null and abs(ix.worst - ix.expect) > 1 and ix.plan_id is null and not ix.young
                         and (ix.last_day is null or ix.latest_on > ix.last_day), false) as fix
           from ix)
  select coalesce(jsonb_agg(jsonb_build_object(
           'route_id', o.route_id, 'hub', o.hub, 'dest', o.dest, 'cabin', o.cabin,
           'departures', o.n, 'sold_out', o.sold, 'sold_out_share', round(o.share, 1), 'average_fare', round(o.fare_week, 2),
           'baseline_fare', round(o.baseline_fare, 2), 'baseline_on', o.baseline_on, 'latest_fare', round(o.latest_fare, 2), 'latest_on', o.latest_on,
           'fare_index', o.fare_index, 'index_matches', o.matches,
           'level', trim_scale(o.level), 'recorded', o.recorded, 'steps', trim_scale(round((o.level - v_launch) / v_step, 1)),
           'move', o.move, 'new_level', trim_scale(o.new_level), 'new_steps', trim_scale(round((o.new_level - v_launch) / v_step, 1)),
           'change_pct', case when o.level > 0 then trim_scale(round((o.new_level / o.level - 1) * 100, 1)) end,
           'reason', o.reason, 'contested', o.contested, 'floor', trim_scale(o.floor_pct), 'cap', trim_scale(o.cap_pct), 'new_route', o.young,
           'planned', o.plan_id is not null, 'plan_id', o.plan_id, 'applied', o.applied, 'seen_on', o.seen_on,
           -- what Put on the fare plan writes: every level that changes, and a hold that follows a step down
           'to_plan', o.plan_id is null and ((o.move in ('up', 'down') and o.new_level <> o.level) or o.k = 'held'),
           -- a change that sets it back to its level (manual §5, since 21 Oct)
           'fix', o.fix,
           'fix_reason', case when o.fix then format('captured fare at %s%%, level %s%%', trim_scale(round(o.worst, 1)), trim_scale(o.expect)) end)
           order by o.hub, o.dest, o.cabin desc), '[]'::jsonb)
    into v_rows from fx o;

  -- the game's Ticket price adjustments, route by route only (manual §5, since 21 Oct: never a whole base, so a route
  -- under 7 days old is never touched). Each sets the level with the baseline default price, and each direction is a
  -- change of its own (From A to B, From B to A). First the set-back changes (fix), then the week's moves, each in the
  -- routes' order (hub, dest): for each route, when both cabins go to the same level, one action each way with both
  -- classes ticked; otherwise one each way for each cabin, economy first. A route whose levels don't change gets no move.
  for v_r in select x.fix, x.hub, x.dest,
                    jsonb_agg(jsonb_build_object('cabin', x.cabin, 'level', x.level, 'reason', x.reason) order by x.cabin = 'business') as moves
               from (select true as fix, e ->> 'route_id' as route_id, e ->> 'hub' as hub, e ->> 'dest' as dest, e ->> 'cabin' as cabin,
                            (e ->> 'level')::numeric as level, e ->> 'fix_reason' as reason
                       from jsonb_array_elements(v_rows) e
                      where (e ->> 'fix')::boolean
                     union all
                     select false, e ->> 'route_id', e ->> 'hub', e ->> 'dest', e ->> 'cabin', (e ->> 'new_level')::numeric, null
                       from jsonb_array_elements(v_rows) e
                      where (e ->> 'new_level')::numeric <> (e ->> 'level')::numeric) x
              group by x.fix, x.route_id, x.hub, x.dest
              order by x.fix desc, x.hub, x.dest loop
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
      foreach v_dir in array array[jsonb_build_array(v_r.hub, v_r.dest), jsonb_build_array(v_r.dest, v_r.hub)] loop
        v_n := v_n + 1;
        v_actions := v_actions || jsonb_build_object(
          'n', v_n, 'route', v_r.hub || '–' || v_r.dest, 'classes', v_change -> 'classes', 'from', v_dir ->> 0, 'to', v_dir ->> 1,
          'level', trim_scale(v_lv), 'sign', case when v_lv >= 100 then '+' else '-' end, 'pct', trim_scale(abs(v_lv - 100)),
          'baseline', 'default price', 'fix', v_r.fix, 'reason', v_change ->> 'reason',
          'text', format('From %s to %s: %s%s%% of the default price, %s', v_dir ->> 0, v_dir ->> 1,
                         case when v_lv >= 100 then '+' else '−' end, trim_scale(abs(v_lv - 100)), v_words));
      end loop;
    end loop;
  end loop;

  return jsonb_build_object(
    'airline_id', p_airline_id, 'as_of', private.fig_ts(p_as_of), 'week_of', v_week,
    'from', private.fig_ts(p_as_of - interval '7 days'), 'to', private.fig_ts(p_as_of),
    'settings', jsonb_build_object('step_pts', v_step, 'up_share', v_up, 'down_share', v_down, 'min_departures', v_min,
                                   'hold_weeks', v_hold, 'cap_pts', v_cap, 'launch_pct', v_launch, 'cap_pct', v_launch + v_cap,
                                   'floor_pct', v_floor, 'new_route_days', v_new_days, 'capacity_hold_days', v_added_days,
                                   'baseline_day', v_base_day),
    'scan', case when v_scan is null then null else jsonb_build_object('id', v_scan, 'taken_at', private.fig_ts(v_scan_at)) end,
    'moves', jsonb_build_object(
      'up', (select count(*) from jsonb_array_elements(v_rows) e where e ->> 'move' = 'up'),
      'hold', (select count(*) from jsonb_array_elements(v_rows) e where e ->> 'move' = 'hold'),
      'down', (select count(*) from jsonb_array_elements(v_rows) e where e ->> 'move' = 'down')),
    'to_plan', (select count(*) from jsonb_array_elements(v_rows) e where (e ->> 'to_plan')::boolean),
    'planned', (select count(*) from jsonb_array_elements(v_rows) e where (e ->> 'planned')::boolean),
    'off_level', (select count(distinct e ->> 'route_id') from jsonb_array_elements(v_rows) e where (e ->> 'fix')::boolean),
    'routes', v_rows, 'actions', v_actions,
    'notes', jsonb_build_array(
      'The fare index compares each flight of the latest captured day with its direction''s fare on 21 Oct 2026, when every route was at its launch level (or its first captured fare, for a route launched later), times the launch level. A route more than 1 point off its level gets a change that sets it back, first in the list, unless it''s on the fare plan this week, new, or not captured since its newest flight launched.'));
end
$function$
;

-- ============================================================ 7. filled back now (data only)
-- Every world's captured flights still without them get their route and aircraft (private.fill_flight_links(), the rule
-- the capture follows from now on), then every route day still without its route gets the airline's route on its
-- airports, either way round: one that isn't removed first, then the one that way round. Counts and times only.
do $backfill$
declare
  t0 timestamptz := clock_timestamp(); t1 timestamptz; ms_f int; ms_d int; w record; v jsonb;
  n_routes int := 0; n_aircraft int := 0; n_days int; b record; a record; bd record; ad record;
begin
  select count(*) as n, count(f.route_id) as with_route, count(f.aircraft_id) as with_aircraft into b from public.game_flights f;
  select count(*) as n, count(d.route_id) as with_route into bd from public.route_days d;
  for w in select x.id from public.worlds x order by x.id loop
    v := private.fill_flight_links(w.id);
    n_routes := n_routes + (v ->> 'routes')::int;
    n_aircraft := n_aircraft + (v ->> 'aircraft')::int;
  end loop;
  ms_f := round(extract(epoch from clock_timestamp() - t0) * 1000);

  t1 := clock_timestamp();
  update public.route_days d
     set route_id = (select r.id from public.routes r
                      where r.airline_id = d.airline_id
                        and ((r.hub_code, r.dest_code) = (d.origin_code, d.dest_code) or (r.hub_code, r.dest_code) = (d.dest_code, d.origin_code))
                      order by r.removed, r.hub_code <> d.origin_code, r.id limit 1)
   where d.route_id is null
     and exists (select 1 from public.routes r where r.airline_id = d.airline_id
                    and ((r.hub_code, r.dest_code) = (d.origin_code, d.dest_code) or (r.hub_code, r.dest_code) = (d.dest_code, d.origin_code)));
  get diagnostics n_days = row_count;
  ms_d := round(extract(epoch from clock_timestamp() - t1) * 1000);

  select count(*) as n, count(f.route_id) as with_route, count(f.aircraft_id) as with_aircraft,
         count(*) filter (where f.route_id is null and (f.origin_code is null or f.dest_code is null)) as no_airports,
         count(*) filter (where f.route_id is null and f.origin_code is not null and f.dest_code is not null) as no_route,
         count(*) filter (where f.aircraft_id is null and coalesce(f.registration, f.maint_registration) is null) as no_registration,
         count(*) filter (where f.aircraft_id is null and coalesce(f.registration, f.maint_registration) is not null) as not_ours
    into a from public.game_flights f;
  select count(*) as n, count(d.route_id) as with_route into ad from public.route_days d;
  raise notice '%', format('game_flights filled back: %s routes and %s aircraft in %s ms (%s rows: with a route %s before, %s now; with an aircraft %s before, %s now); still without a route: %s with no airports, %s on airports the airline has no route on; without an aircraft: %s naming no registration, %s naming one that isn''t an aircraft of the world',
                           n_routes, n_aircraft, ms_f, a.n, b.with_route, a.with_route, b.with_aircraft, a.with_aircraft,
                           a.no_airports, a.no_route, a.no_registration, a.not_ours);
  raise notice '%', format('route_days filled back: %s routes in %s ms (%s rows: with a route %s before, %s now); still without: %s, on airports the airline has no route on',
                           n_days, ms_d, ad.n, bd.with_route, ad.with_route, ad.n - ad.with_route);
end
$backfill$;

-- ============================================================ 8. access and descriptions
-- The replaced functions stay internal: nobody outside the database calls them.
revoke all on function private.fill_flight_links(bigint) from public, anon, authenticated, service_role;
revoke all on function private.merge_flight(bigint, bigint) from public, anon, authenticated, service_role;
revoke all on function private.capture_page(bigint) from public, anon, authenticated, service_role;
revoke all on function private.capture_refresh(bigint) from public, anon, authenticated, service_role;
revoke all on function private.take_snapshot(bigint, date, timestamptz, text, boolean) from public, anon, authenticated, service_role;
revoke all on function private.fig_fare_ladder(bigint, timestamptz) from public, anon, authenticated, service_role;

comment on function private.fill_flight_links(bigint) is 'The route and aircraft of a world''s captured flights that don''t have them yet (no other row is touched): the route by the schedule''s leg with that number and direction, else the airline''s route on its airports, either way round, one that isn''t removed first (since 22 Oct), then the one that way round; the aircraft by the registration the loads page or the statement names. Since 22 Oct called after every statement and loads page (private.capture_page()), by private.capture_refresh() and by the daily snapshot before its flows (private.take_snapshot()), so each flight has its links from the evening it is captured and each route day its route. Returns how many routes and aircraft it filled.';
comment on function private.merge_flight(bigint, bigint) is 'Joins one money-only game_flights row and one loads-only row into one flight: the loads columns move into the money row, and the loads row goes. Since 22 Oct the joined flight takes the loads row''s route (by its flight number), or none until the capture fills the links right after the matching (private.fill_flight_links()), never the route its money-only row took by its airports; its aircraft is either side''s.';
comment on function private.capture_page(bigint) is 'Parses one stored capture page into the capture tables, using the page''s own capture time throughout: statement lines into game_statement, folded into game_flights and game_payments; events into game_events (with due_at where known); loads into game_flights; the income statement and balance sheet into game_pnl and game_balance (with capture_day), each row''s figures and capture time from the same capture, the latest (#13 pull request 6). Then money and loads are matched, and since 22 Oct, after a statement or loads page, each captured flight of the world still without them gets its route and aircraft (private.fill_flight_links()).';
comment on function private.capture_refresh(bigint) is 'For every airline of our groups in a world: fills flight times and events'' due_at that have become known, then matches money to loads, and since 22 Oct fills the route and aircraft of every captured flight still without them (private.fill_flight_links(); links in its answer). Run once after the airports are loaded (#13, pull request 4); the capture does the same for one airline after each page.';
comment on function private.take_snapshot(bigint, date, timestamp with time zone, text, boolean) is 'The daily snapshot of a world''s capture day (design §7): point-in-time figures (fleet, schedule, cash) as at p_at (default now) into airline_days for each active airline of our groups, with source (capture, fallback or backfill) and whether the day''s capture was complete; then (p_flows), once each captured flight still without them has its route and aircraft (private.fill_flight_links(), since 22 Oct, so each route day written has its route; links in its answer), the flows of that UTC day and the two before. A later snapshot replaces the point-in-time figures, but a fallback or backfill never replaces one from a complete capture. Called by the capture when a day completes; pull request 7''s 10:00 UTC fallback calls it too.';
comment on column public.game_flights.route_id is 'The route, by the schedule''s leg with that number and direction, else by its airports, either way round, one that isn''t removed first (filled by private.fill_flight_links after each statement and loads page since 22 Oct, and filled back that day)';
comment on column public.game_flights.aircraft_id is 'The aircraft, by the registration the loads page or the statement names (filled by private.fill_flight_links after each statement and loads page since 22 Oct, and filled back that day)';
comment on column public.route_days.route_id is 'The route: the day''s flights'' (game_flights.route_id, linked before the snapshot writes the day since 22 Oct), else the airline''s route on the airports, either way round, one that isn''t removed first (filled back 22 Oct); set to null if the route row is deleted later (the airports keep the history)';
comment on function public.fare_ladder(bigint, timestamptz) is 'The fare ladder for one airline (manual §5, since 21 Oct; specs docs/specs/2026-10-21-fare-ladder.md, docs/specs/2026-10-21-fare-actions-by-route.md, docs/specs/2026-10-21-frequencies-and-fares.md and docs/specs/2026-10-21-competition-analysis.md §2): this Saturday''s move for each route and cabin, the changes that set a route back to its level, and the game actions that make them. routes: each route not removed that flies (in economy, and in business where its aircraft have business seats) or has flights captured in the 7 days before the moment, with its departures, departures sold out (that cabin''s load at 100%), the sold-out share and the average fare over those 7 days (game_flights, matched to the route either way round); its level as a % of the game''s default price (the latest the fare plan recorded before this Saturday, else settings.fare_launch_pct) and steps above launch; the fare index: each flight of the latest captured day (latest_on, its average latest_fare) against its direction''s baseline, times the launch level, the baseline being the direction''s fare on the latest captured day on or before 21 Oct 2026, when every route was at its launch level (Gitesh), or for a route launched later its first captured fare if captured in its first growth_new_route_days days (a day''s fare: its flights'' lowest, else route_days'' average fare in that cabin, eco_fare_avg and, since 22 Oct, bus_fare_avg on a day with business passengers, so a baseline survives the flights'' archiving in both cabins; baseline_fare and baseline_on, the directions'' average and latest day); fare_index the flights'' average, index_matches false when any flight is more than 1 point off the level the game should show (this week''s new level once the captures see it); the move (up when every departure sold out, hold at fare_ladder_down_share to 99%, down under it; hold under fare_ladder_min_departures, under growth_new_route_days old, for fare_ladder_hold_weeks after a recorded step down, while the newest rotation is under fare_ladder_capacity_hold_days old on a route older than that (a flight added: "judged at its new size from ..."; a frequency taken away isn''t tracked, its rotation is deleted), and, since 21 Oct, while a rival threatens the pair (private.competition_threats(), as competition() lists them: a rival who started there or added competition_threat_min_weekly departures a week in a scan of the 7 days before the moment; "rival Air China started here on 22 Oct: paused until 29 Oct", the one paused longest), checked after planned, new, few, held and added and before the sold-out share; never above launch + fare_ladder_cap_pts, nor under launch or, where another player flies the pair, world_rules.fare_floor_pct), the new level and the reason in words; planned, applied and seen_on for a move recorded since this Saturday; to_plan, what Put on the fare plan writes; fix, a change that sets it back to its level (index_matches false, not on the fare plan this week, not a new route, and captured since its newest rotation launched), with fix_reason ("captured fare at 100%, level 110%"). moves counts the moves, off_level the routes set back. actions: the Ticket price adjustments (baseline default price), route by route only, never a whole base (so a route under 7 days old is never touched; since 21 Oct): first the set-back changes (fix true, with the reason), then the week''s moves, each in the routes'' order (hub, dest), one action each way (From hub to dest, then From dest to hub) with classes ["economy","business"] when both cabins go to the same level, otherwise one each way for each cabin, economy first; a route whose levels don''t change gets no move. Each action has n, route, classes, from, to, level, sign, pct, baseline, fix, reason (a set-back''s) and text, the text in the game''s words naming the classes. settings: the numbers used, with capacity_hold_days and baseline_day. notes: how the index reads. Staff only; runs as owner and checks the caller itself.';

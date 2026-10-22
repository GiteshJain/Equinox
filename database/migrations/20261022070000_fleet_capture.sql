-- The fleet in the evening capture (22 Oct 2026; spec docs/specs/2026-10-22-fleet-capture.md, option B of brief
-- docs/briefs/2026-10-22-fleet-capture.md; manual §7).
--
-- Why (Gitesh, 22 Oct: "B and C, as maintenance and turns can change as the world grows"): N003AW (JFK) ran at 0.0%
-- maintenance in the game from 18 to 22 Oct while the planner showed 132%, and nothing flagged it. Capture all airlines
-- 1.6 reads every fleet page of every airline after its other pages and sends each as a new page kind, fleet. This keeps
-- each aircraft's figures night by night (what C, fitting the planner's maintenance figure, will learn from) and lists
-- what needs a look.
--
-- Adds and replaces (CREATE OR REPLACE, the same arguments); drops and renames nothing, so it can be applied from the
-- chat. No data changes but descriptions.
--   1. public.game_fleet: one row per aircraft per capture day (10:00 to 10:00 UTC), the latest capture of the day
--      winning, kept for good (about 140 rows a night). RLS with one staff read rule; staff read it, only the capture
--      writes it (through capture_ingest(), as owner).
--   2. The page kind fleet: capture_ingest() takes it; private.capture_fleet() reads a fleet page into game_fleet;
--      private.capture_page() calls it; private.capture_expect() gives the fleet and its count on the fleet list;
--      private.capture_check() and private.capture_judge() judge it (#21): short with no aircraft rows, broken when it
--      doesn't read. private.capture_airline_verdict() judges an airline's day with its fleet pages too, when it has some,
--      and private.fig_capture_status() (capture_status(), and so system_status()) gives them beside each airline (fleet)
--      and counts them in its latest page. An airline with no fleet pages is judged exactly as before.
--   3. public.fleet_checks(p_world_id, p_as_of), staff only, its own 30 s limit like the other figures, and its builder
--      private.fig_fleet_checks(): from the latest night's game_fleet, the problems (maintenance under
--      maintenance_min_pct, no pilots, seats not matching the planner's cabin, in the game but not the planner, in the
--      planner but not the game when every fleet page of the airline came in ok), each kind's count, the night, and each
--      airline's fleet with its problems marked.
-- New private functions get no grants; fleet_checks() is for staff (signed in), as the other figures.

select set_config('equinox.actor', 'migration', true),
       set_config('equinox.actor_detail', '20261022070000_fleet_capture', true);

-- ============================================================ 1. the table
create table public.game_fleet (
  id bigint generated always as identity primary key,
  world_id bigint not null,
  airline_id bigint not null,
  capture_day date not null,
  aircraft_id bigint,
  registration text not null,
  type_name text,
  nickname text,
  location_from text,
  location_to text,
  flight text,
  age_years numeric(5,1),
  condition_pct numeric(5,1),
  maintenance_pct numeric(7,1),
  seats_y integer,
  seats_c integer,
  seats_f integer,
  pilots boolean,
  owned boolean,
  contract_status text,
  fleet_game_id integer,
  fleet_name text,
  captured_at timestamp with time zone not null,
  constraint game_fleet_world_fkey foreign key (world_id) references public.worlds (id),
  constraint game_fleet_airline_fkey foreign key (airline_id, world_id) references public.airlines (id, world_id),
  -- an aircraft removed from the planner keeps its nights, matched to nothing
  constraint game_fleet_aircraft_fkey foreign key (aircraft_id, world_id) references public.aircraft (id, world_id)
    on delete set null (aircraft_id),
  constraint game_fleet_day_key unique (airline_id, capture_day, registration)
);
create index game_fleet_world_day_idx on public.game_fleet (world_id, capture_day);
create index game_fleet_aircraft_id_idx on public.game_fleet (aircraft_id);

alter table public.game_fleet enable row level security;
create policy "staff read" on public.game_fleet for select to authenticated using ((select public.is_planner_user()));
revoke all on table public.game_fleet from public, anon, authenticated;
grant select on table public.game_fleet to authenticated;

-- ============================================================ 2. the page kind
-- a fleet page as Capture all airlines 1.6 sends it (capture/capture_all.user.js, readFleetPage() and fleetPayload()):
-- {run, page, of, fleet: {id, name}, fleets: [{id, name, aircraft}], aircraft: [...]}, or error in place of aircraft
create or replace function private.capture_fleet(p_raw_id bigint)
 returns integer
 language plpgsql
 set search_path to ''
as $function$
declare r record; d jsonb; e jsonb; n int := 0; v_day date; v_fleet_id int; v_fleet text; v_reg text; v_ac bigint;
begin
  select x.id, x.world_id, x.airline_id, x.rows, x.captured_at into r from public.game_capture_raw x where x.id = p_raw_id and x.kind = 'fleet';
  if not found then raise exception 'no fleet page %', p_raw_id; end if;
  d := r.rows;
  if jsonb_typeof(d) is distinct from 'object' then raise exception 'not a fleet page as the capture reads it'; end if;
  if d ? 'error' then raise exception '%', left(coalesce(d ->> 'error', 'no reason given'), 200); end if;
  if jsonb_typeof(d -> 'aircraft') is distinct from 'array' then raise exception 'no aircraft list'; end if;
  v_day := private.capture_day(r.world_id, r.captured_at);
  v_fleet_id := private.json_int(d #> '{fleet,id}');
  v_fleet := left(nullif(btrim(d #>> '{fleet,name}'), ''), 80);
  for e in select x from jsonb_array_elements(d -> 'aircraft') x loop
    v_reg := upper(nullif(btrim(e ->> 'registration'), ''));
    if v_reg is null then raise exception 'an aircraft row without its registration'; end if;
    -- the planner's aircraft: by registration within the airline (null when the planner doesn't know it)
    select a.id into v_ac from public.aircraft a
     where a.airline_id = r.airline_id and upper(a.registration) = v_reg
     order by a.status = 'retired', a.id desc limit 1;
    insert into public.game_fleet as g (world_id, airline_id, capture_day, aircraft_id, registration, type_name, nickname,
           location_from, location_to, flight, age_years, condition_pct, maintenance_pct, seats_y, seats_c, seats_f, pilots,
           owned, contract_status, fleet_game_id, fleet_name, captured_at)
    values (r.world_id, r.airline_id, v_day, v_ac, v_reg, left(nullif(btrim(e ->> 'type'), ''), 120), left(nullif(btrim(e ->> 'nickname'), ''), 120),
            upper(nullif(btrim(e ->> 'from'), '')), upper(nullif(btrim(e ->> 'to'), '')), left(nullif(btrim(e ->> 'flight'), ''), 20),
            private.json_num(e -> 'age_years'), private.json_num(e -> 'condition_pct'), private.json_num(e -> 'maintenance_pct'),
            private.json_int(e -> 'y'), private.json_int(e -> 'c'), private.json_int(e -> 'f'),
            case when jsonb_typeof(e -> 'pilots') = 'boolean' then (e ->> 'pilots')::boolean end,
            case when jsonb_typeof(e -> 'owned') = 'boolean' then (e ->> 'owned')::boolean end,
            left(nullif(btrim(e ->> 'contract'), ''), 40), v_fleet_id, v_fleet, r.captured_at)
    on conflict on constraint game_fleet_day_key do update set
      aircraft_id = excluded.aircraft_id, type_name = excluded.type_name, nickname = excluded.nickname,
      location_from = excluded.location_from, location_to = excluded.location_to, flight = excluded.flight,
      age_years = excluded.age_years, condition_pct = excluded.condition_pct, maintenance_pct = excluded.maintenance_pct,
      seats_y = excluded.seats_y, seats_c = excluded.seats_c, seats_f = excluded.seats_f, pilots = excluded.pilots,
      owned = excluded.owned, contract_status = excluded.contract_status, fleet_game_id = excluded.fleet_game_id,
      fleet_name = excluded.fleet_name, captured_at = excluded.captured_at
    where excluded.captured_at >= g.captured_at;
    n := n + 1;
  end loop;
  return n;
end
$function$;

CREATE OR REPLACE FUNCTION public.capture_ingest(p_key text, p_airline text, p_kind text, p_page text, p_rows jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_world bigint; v_res jsonb;
begin
  v_world := private.capture_key_world(p_key);
  if v_world is null then return jsonb_build_object('ok', false, 'error', 'bad key'); end if;
  if p_kind is null or p_kind not in ('statement', 'events', 'loads', 'pnl', 'balance', 'fleet', 'html') then
    return jsonb_build_object('ok', false, 'error', 'bad kind');
  end if;
  perform set_config('equinox.actor', 'capture', true);
  v_res := private.capture_store(v_world, p_airline, p_kind, p_page, p_rows, now());
  -- the capture panel prints rows (or error) after "<airline> · loads ": after the loads page, the airline's verdict goes
  -- there (#21), so the userscript needs no change; the count stays under count
  if p_kind = 'loads' and v_res ? 'airline_verdict' then
    v_res := v_res || jsonb_build_object('count', coalesce(v_res -> 'rows', '0'::jsonb), 'rows', private.capture_panel_words(v_res));
  end if;
  return v_res;
end
$function$;

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

  elsif r.kind = 'fleet' then
    -- a fleet page (since 22 Oct): each aircraft into game_fleet, the latest capture of the day winning
    n := private.capture_fleet(p_raw_id);
  end if;
  return jsonb_build_object('ok', true, 'kind', r.kind, 'rows', n);
end
$function$;

CREATE OR REPLACE FUNCTION private.capture_expect(p_raw_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare r record; v_from timestamptz; n int; v_med numeric; v_nights int; v_day date; d jsonb;
begin
  select x.id, x.world_id, x.airline_id, x.kind, x.captured_at into r from public.game_capture_raw x where x.id = p_raw_id;
  if not found then return '{}'::jsonb; end if;
  if r.kind = 'loads' then
    -- the page's window is the game's "-24h": the flights that departed in the 24 hours before the capture
    v_from := r.captured_at - interval '24 hours';
    -- the aircraft that have flown: each registration the airline's captured loads named before this page (a new
    -- aircraft counts from the first capture that shows it flying; on 15 Oct the aircraft filed 13 Oct hadn't flown yet)
    with flown as (
      select distinct f.registration from public.game_flights f
       where f.airline_id = r.airline_id and f.registration is not null and f.loads_captured_at < r.captured_at)
    select count(*)::int into n
      from public.flight_legs l
      join public.rotations ro on ro.id = l.rotation_id
      left join public.aircraft ac on ac.id = l.aircraft_id
     cross join lateral generate_series(date_trunc('day', v_from at time zone 'UTC'), date_trunc('day', r.captured_at at time zone 'UTC'),
                                        interval '1 day') d(day)
     cross join lateral (select (d.day + make_interval(mins => l.dep_utc_min::int)) at time zone 'UTC' as dep_at) x
     where l.airline_id = r.airline_id and l.dep_utc_min is not null
       and extract(isodow from d.day)::smallint = any (l.days_utc)
       -- a rotation counts from the day after it launched: an aircraft's first day is rarely flown in full (on 13 Oct,
       -- the day new aircraft were filed, none of their flights had flown by the evening's capture)
       and (ro.launched_on is null or ro.launched_on < d.day::date)
       and x.dep_at > v_from and x.dep_at <= r.captured_at
       -- a leg with an aircraft counts once that aircraft has flown; a leg with none counts as before
       and (l.aircraft_id is null or exists (select 1 from flown fl where fl.registration = ac.registration));
    return jsonb_build_object('scheduled', n, 'window_from', private.fig_ts(v_from), 'window_to', private.fig_ts(r.captured_at));
  elsif r.kind = 'statement' then
    v_day := private.capture_day(r.world_id, r.captured_at);
    with nights as (
      select distinct on (private.capture_day(p.world_id, p.captured_at)) private.capture_day(p.world_id, p.captured_at) as day,
             private.capture_statement_lines(p.rows) as lines
        from public.game_capture_raw p
       where p.airline_id = r.airline_id and p.kind = 'statement' and p.captured_at < r.captured_at
         and private.capture_day(p.world_id, p.captured_at) < v_day
       order by private.capture_day(p.world_id, p.captured_at) desc, p.captured_at desc, p.id desc),
    recent as (select n.lines from nights n order by n.day desc limit 7)
    select percentile_cont(0.5) within group (order by x.lines)::numeric, count(*)::int into v_med, v_nights from recent x;
    return jsonb_build_object('median_lines', round(v_med, 1), 'nights', v_nights);
  elsif r.kind = 'fleet' then
    -- the fleet the page shows (null for the fleet list when it didn't read), which page of how many the capture read
    -- that run, and how many aircraft the airline's fleet list said it holds
    select x.rows into d from public.game_capture_raw x where x.id = p_raw_id;
    if jsonb_typeof(d) <> 'object' then return '{}'::jsonb; end if;
    return jsonb_build_object(
      'fleet', nullif(btrim(d #>> '{fleet,name}'), ''), 'fleet_id', private.json_int(d #> '{fleet,id}'),
      'page', private.json_int(d -> 'page'), 'of', private.json_int(d -> 'of'),
      'listed', (select private.json_int(e -> 'aircraft')
                   from jsonb_array_elements(case when jsonb_typeof(d -> 'fleets') = 'array' then d -> 'fleets' else '[]'::jsonb end) e
                  where jsonb_typeof(d -> 'fleet') = 'object' and e -> 'id' is not distinct from d #> '{fleet,id}'
                  limit 1));
  end if;
  return '{}'::jsonb;
end
$function$;

CREATE OR REPLACE FUNCTION private.capture_check(p_raw_id bigint, p_parse jsonb, p_expect jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare r record; v_err text; v_read int; v_cash boolean; v_exp jsonb; v_j jsonb; v_lmin numeric; v_smin numeric;
begin
  select x.id, x.world_id, x.airline_id, x.kind, x.rows, x.captured_at into r from public.game_capture_raw x where x.id = p_raw_id;
  if not found or r.kind not in ('statement', 'events', 'loads', 'pnl', 'balance', 'fleet') then return null; end if;
  v_err := case when coalesce((p_parse ->> 'ok')::boolean, false) then null else coalesce(p_parse ->> 'error', 'no answer from the reader') end;
  v_read := case when jsonb_typeof(p_parse -> 'rows') = 'number' then (p_parse ->> 'rows')::int end;
  v_exp := coalesce(p_expect, private.capture_expect(p_raw_id));
  if r.kind = 'balance' then
    -- the cash account as the reader takes it: account 2800 in a row's first or fourth cell, with a figure beside it
    v_cash := exists (select 1 from jsonb_array_elements(case when jsonb_typeof(r.rows) = 'array' then r.rows else '[]'::jsonb end) e(row_)
                       where jsonb_typeof(e.row_) = 'array'
                         and ((jsonb_array_length(e.row_) >= 3 and e.row_ ->> 0 = '2800' and public.as_num(e.row_ ->> 2) is not null)
                           or (jsonb_array_length(e.row_) >= 6 and e.row_ ->> 3 = '2800' and public.as_num(e.row_ ->> 5) is not null)));
  end if;
  select coalesce((select (s.value #>> '{}')::numeric from public.settings s
                    where s.world_id = r.world_id and s.airline_id is null and s.key = 'capture_loads_min_share'), 0.9),
         coalesce((select (s.value #>> '{}')::numeric from public.settings s
                    where s.world_id = r.world_id and s.airline_id is null and s.key = 'capture_statement_min_share'), 0.5)
    into v_lmin, v_smin;
  v_j := private.capture_judge(r.kind, v_read, v_err, v_cash, v_exp, v_lmin, v_smin);
  update public.game_capture_raw x set verdict = v_j ->> 'verdict', verdict_note = v_j ->> 'note', verdict_facts = v_j -> 'facts'
   where x.id = p_raw_id;
  return jsonb_build_object('kind', r.kind, 'verdict', v_j ->> 'verdict', 'note', v_j ->> 'note', 'at', private.fig_ts(r.captured_at))
         || (v_j -> 'facts');
end
$function$;

CREATE OR REPLACE FUNCTION private.capture_judge(p_kind text, p_read integer, p_error text, p_cash boolean, p_expect jsonb, p_loads_min numeric, p_statement_min numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$
declare v text := 'ok'; v_note text; v_exp numeric; v_label text; v_facts jsonb;
begin
  if p_kind is null or p_kind not in ('statement', 'events', 'loads', 'pnl', 'balance', 'fleet') then return null; end if;
  v_label := case p_kind when 'pnl' then 'income statement' when 'balance' then 'balance sheet'
                         when 'fleet' then 'fleet ' || coalesce(nullif(btrim(p_expect ->> 'fleet'), ''), 'list') else p_kind end;
  v_facts := coalesce(p_expect, '{}'::jsonb) || jsonb_build_object('read', p_read);
  if p_error is not null then
    return jsonb_build_object('verdict', 'broken', 'note', v_label || ' didn''t read (' || left(p_error, 160) || ')',
                              'facts', v_facts || jsonb_build_object('error', left(p_error, 300)));
  end if;
  if p_kind = 'loads' then
    v_exp := (p_expect ->> 'scheduled')::numeric;
    v_facts := v_facts || jsonb_build_object('min_share', p_loads_min,
                                             'share', case when v_exp > 0 then round(coalesce(p_read, 0) / v_exp, 3) end);
    if v_exp > 0 and coalesce(p_read, 0) < p_loads_min * v_exp then v := 'short'; end if;
    v_note := case when v_exp is null then format('loads %s flights', coalesce(p_read, 0))
                   when v_exp = 0 then format('loads %s flights, none scheduled', coalesce(p_read, 0))
                   else format('loads %s of %s flights', coalesce(p_read, 0), v_exp) end;
  elsif p_kind = 'statement' then
    v_exp := (p_expect ->> 'median_lines')::numeric;
    v_facts := v_facts || jsonb_build_object('min_share', p_statement_min);
    if coalesce(p_read, 0) = 0 then
      v := 'short'; v_note := 'statement: no lines';
    elsif v_exp > 0 and p_read < p_statement_min * v_exp then
      v := 'short'; v_note := format('statement %s line%s, usually about %s', p_read, case when p_read = 1 then '' else 's' end, round(v_exp));
    else
      v_note := format('statement %s line%s', p_read, case when p_read = 1 then '' else 's' end) || case when v_exp > 0 then format(' (usually about %s)', round(v_exp)) else '' end;
    end if;
  elsif p_kind = 'fleet' then
    -- a fleet page (since 22 Oct): short with no aircraft rows
    if coalesce(p_read, 0) = 0 then
      v := 'short'; v_note := v_label || ': no aircraft rows';
    else
      v_note := format('%s %s aircraft', v_label, p_read);
    end if;
  elsif p_kind = 'balance' then
    v_facts := v_facts || jsonb_build_object('cash', coalesce(p_cash, false));
    if not coalesce(p_cash, false) then
      v := 'broken'; v_note := 'balance sheet without the cash account (2800)';
    else
      v_note := format('balance sheet %s row%s, the cash account there', coalesce(p_read, 0), case when p_read = 1 then '' else 's' end);
    end if;
  else
    if coalesce(p_read, 0) = 0 then
      v := 'short'; v_note := v_label || ': no rows';
    else
      v_note := format('%s %s row%s', v_label, p_read, case when p_read = 1 then '' else 's' end);
    end if;
  end if;
  return jsonb_build_object('verdict', v, 'note', v_note, 'facts', v_facts);
end
$function$;

CREATE OR REPLACE FUNCTION private.capture_airline_verdict(p_airline_id bigint, p_at timestamp with time zone)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  with a as (select al.world_id, private.capture_day(al.world_id, p_at) as day from public.airlines al where al.id = p_airline_id),
  span as (select private.capture_day_start(a.world_id, a.day) as from_at from a),
  k as (select * from unnest(array['events', 'statement', 'pnl', 'balance', 'loads'],
                             array['events', 'statement', 'income statement', 'balance sheet', 'loads']) with ordinality as k(kind, label, o)),
  latest as (
    select distinct on (r.kind) r.kind, r.verdict, r.verdict_note, r.captured_at
      from public.game_capture_raw r, span
     where r.airline_id = p_airline_id and r.kind in ('events', 'statement', 'pnl', 'balance', 'loads')
       and r.captured_at >= span.from_at and r.captured_at <= p_at
     order by r.kind, r.captured_at desc, r.id desc),
  j as (select k.kind, k.label, k.o, l.verdict, l.verdict_note as note, l.captured_at from k left join latest l on l.kind = k.kind),
  v0 as (select case when bool_or(j.verdict = 'broken') then 'broken'
                     when bool_or(j.verdict = 'short') or bool_or(j.captured_at is null) then 'short'
                     when bool_or(j.verdict = 'ok') then 'ok' end as verdict
           from j),
  ja as (select max(j.captured_at) as at,
                string_agg(case when j.captured_at is null then j.label || ' not captured'
                                when j.verdict in ('short', 'broken') then j.note end, '; ' order by j.o) as notes,
                coalesce(jsonb_agg(j.kind order by j.o) filter (where j.captured_at is null), '[]'::jsonb) as missing,
                jsonb_object_agg(j.kind, case when j.captured_at is not null
                                              then jsonb_build_object('verdict', j.verdict, 'note', j.note, 'at', private.fig_ts(j.captured_at)) end) as pages
           from j),
  -- the fleet pages (since 22 Oct, spec docs/specs/2026-10-22-fleet-capture.md): the latest page of each fleet that day;
  -- an airline with no fleet pages is judged on its other pages alone, as before
  fl as (
    select distinct on (coalesce(r.rows #>> '{fleet,id}', r.rows #>> '{fleet,name}', 'list'))
           r.verdict, r.verdict_note, r.captured_at, private.json_int(r.verdict_facts -> 'read') as n
      from public.game_capture_raw r, span
     where r.airline_id = p_airline_id and r.kind = 'fleet' and r.captured_at >= span.from_at and r.captured_at <= p_at
     order by coalesce(r.rows #>> '{fleet,id}', r.rows #>> '{fleet,name}', 'list'), r.captured_at desc, r.id desc),
  fv as (select count(*)::int as pages, (count(*) filter (where fl.verdict = 'ok'))::int as ok,
                case when bool_or(fl.verdict = 'broken') then 'broken' when bool_or(fl.verdict = 'short') then 'short'
                     when bool_or(fl.verdict = 'ok') then 'ok' end as verdict,
                string_agg(fl.verdict_note, '; ' order by fl.captured_at) filter (where fl.verdict in ('short', 'broken')) as notes,
                coalesce(sum(fl.n), 0)::int as aircraft, max(fl.captured_at) as at
           from fl),
  v as (select case when v0.verdict = 'broken' or fv.verdict = 'broken' then 'broken'
                    when v0.verdict = 'short' or fv.verdict = 'short' then 'short'
                    else v0.verdict end as verdict
          from v0, fv)
  select jsonb_build_object(
    'capture_day', (select a.day from a),
    'at', private.fig_ts(greatest(ja.at, fv.at)),
    'verdict', v.verdict,
    'words', case when v.verdict = 'ok' then 'all good'
                  when v.verdict is null then 'not checked (captured before the page checks)'
                  else v.verdict || ': ' || concat_ws('; ', ja.notes, fv.notes) end,
    'missing', ja.missing,
    'pages', ja.pages || case when fv.pages > 0 then jsonb_build_object('fleet', jsonb_build_object(
               'verdict', fv.verdict,
               'note', case when fv.verdict in ('short', 'broken') then fv.notes
                            else format('fleet %s page%s, %s aircraft', fv.pages, case when fv.pages = 1 then '' else 's' end, fv.aircraft) end,
               'at', private.fig_ts(fv.at), 'pages', fv.pages, 'ok', fv.ok, 'aircraft', fv.aircraft)) else '{}'::jsonb end)
    from ja, v, fv
$function$;

CREATE OR REPLACE FUNCTION private.fig_capture_status(p_world_id bigint, p_as_of timestamp with time zone)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  with d as (select (p_as_of at time zone 'UTC')::date as d0),
  al as (select * from private.fig_airlines(p_world_id) where home_code is not null),
  k as (select * from unnest(array['loads', 'statement', 'events', 'pnl', 'balance']) with ordinality as k(kind, o)),
  runs as (select r.airline_id, r.kind, (r.captured_at at time zone 'UTC')::date as day, max(r.captured_at) as at
             from public.game_capture_raw r, d
            where r.world_id = p_world_id and r.captured_at <= p_as_of
              and r.captured_at >= ((d.d0 - 1)::timestamp at time zone 'UTC')
            group by 1, 2, 3),
  fl as (select f.airline_id, f.game_date, count(distinct f.flight_no)::int as n
           from public.game_flights f, d
          where f.world_id = p_world_id and f.flight_no is not null and f.game_date in (d.d0, d.d0 - 1) and f.loads_captured_at <= p_as_of
          group by 1, 2),
  rows_ as (
    select al.airline_id, al.ord, al.iata_code, al.name,
           (select jsonb_object_agg(k.kind, jsonb_build_object('today', private.fig_ts(t.at), 'yesterday', private.fig_ts(y.at)) order by k.o)
              from k left join runs t on t.airline_id = al.airline_id and t.kind = k.kind and t.day = d.d0
                     left join runs y on y.airline_id = al.airline_id and y.kind = k.kind and y.day = d.d0 - 1) as pages,
           (select coalesce(jsonb_agg(k.kind order by k.o), '[]'::jsonb) from k
             where not exists (select 1 from runs t where t.airline_id = al.airline_id and t.kind = k.kind and t.day = d.d0)) as missing,
           (select n from fl where fl.airline_id = al.airline_id and fl.game_date = d.d0) as flights_today,
           (select n from fl where fl.airline_id = al.airline_id and fl.game_date = d.d0 - 1) as flights_yesterday,
           -- the airline's latest page of any kind by the moment, whenever it was (#21, #23; its fleet pages since 22 Oct)
           (select max(r.captured_at) from public.game_capture_raw r
             where r.airline_id = al.airline_id and r.kind in ('statement', 'events', 'loads', 'pnl', 'balance', 'fleet') and r.captured_at <= p_as_of) as last_at
      from al, d),
  judged as (select r.*, case when r.last_at is not null then private.capture_airline_verdict(r.airline_id, r.last_at) end as v from rows_ r)
  select jsonb_build_object(
    'world_id', p_world_id, 'as_of', private.fig_ts(p_as_of), 'today', (select d0 from d), 'yesterday', (select d0 - 1 from d),
    'airlines', coalesce(jsonb_agg(jsonb_build_object(
        'airline_id', r.airline_id, 'code', r.iata_code, 'name', r.name, 'pages', r.pages,
        'flights_today', r.flights_today, 'flights_yesterday', r.flights_yesterday, 'missing', r.missing,
        'status', case when jsonb_array_length(r.missing) = 0 then 'complete' when jsonb_array_length(r.missing) = 5 then 'not captured' else 'missing' end,
        'last_at', private.fig_ts(r.last_at),
        'verdict', r.v -> 'verdict', 'verdict_words', r.v -> 'words', 'verdict_at', r.v -> 'at',
        'verdict_day', r.v -> 'capture_day', 'verdicts', r.v -> 'pages')
        -- that capture day's fleet pages (since 22 Oct), only when it has some
        || case when r.v #> '{pages,fleet}' is not null then jsonb_build_object('fleet', r.v #> '{pages,fleet}') else '{}'::jsonb end
        order by r.ord), '[]'::jsonb))
    from judged r
$function$;

-- ============================================================ 3. the checks
create or replace function private.fig_fleet_checks(p_world_id bigint, p_as_of timestamp with time zone)
 returns jsonb
 language plpgsql
 stable
 set search_path to ''
as $function$
declare v_night date; v_doc jsonb;
begin
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
           c.economy_seats, c.business_seats,
           case when c.seats is not null and c.business_seats is not null and c.economy_seats is not null
                then greatest(c.seats - c.business_seats - c.economy_seats, 0) else 0 end as first_seats
      from public.aircraft a left join public.cabin_configs c on c.id = a.cabin_config_id
     where a.world_id = p_world_id and a.airline_id in (select al.airline_id from al)),
  fl as (
    select f.*, al.ord, al.iata_code, al.min_pct, m.id as planner_id, m.base_code, m.cabin_config_id, m.cabin_code,
           m.economy_seats, m.business_seats, m.first_seats,
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
       and not exists (select 1 from fl where fl.airline_id = a.airline_id and fl.registration = upper(a.registration))),
  kinds as (select * from unnest(array['maintenance', 'crew', 'cabin', 'not_in_planner', 'not_in_game']) with ordinality k(kind, o))
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
            'flight', fl.flight, 'age_years', fl.age_years, 'condition_pct', fl.condition_pct, 'maintenance_pct', fl.maintenance_pct,
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

create or replace function public.fleet_checks(p_world_id bigint default null::bigint, p_as_of timestamp with time zone default now())
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to ''
 set statement_timeout to '30s'
as $function$
begin
  if not private.caller_is_staff() then raise exception 'only planner staff can read the captured figures' using errcode = '42501'; end if;
  return private.fig_fleet_checks(private.fig_world(p_world_id), coalesce(p_as_of, now()));
end
$function$;

-- ============================================================ who may call them
revoke all on function private.capture_fleet(bigint) from public, anon, authenticated, service_role;
revoke all on function private.fig_fleet_checks(bigint, timestamptz) from public, anon, authenticated, service_role;
revoke all on function public.fleet_checks(bigint, timestamptz) from public, anon, authenticated, service_role;
grant execute on function public.fleet_checks(bigint, timestamptz) to authenticated;

-- ============================================================ descriptions
comment on table public.game_fleet is 'The fleet as the game shows it (spec docs/specs/2026-10-22-fleet-capture.md; manual §7): one row per aircraft per capture day (design §2: the evening it was taken, 10:00 to 10:00 UTC), from the evening capture''s fleet pages (Capture all airlines 1.6, page kind fleet), the latest capture of the day winning. Kept for good (about 140 rows a night): the history the planner''s maintenance figure will be fitted to (the brief''s option C). Written only by the capture (capture_ingest(), private.capture_fleet()); staff read it. Read by fleet_checks() (Today, Systems'' Fleet, the Tails pop-up).';
comment on column public.game_fleet.id is 'The row''s own number';
comment on column public.game_fleet.world_id is 'The world';
comment on column public.game_fleet.airline_id is 'The airline whose fleet page it was on';
comment on column public.game_fleet.capture_day is 'The capture day it was read (private.capture_day(): 10:00 to 10:00 UTC, the day the evening started)';
comment on column public.game_fleet.aircraft_id is 'The planner''s aircraft with this registration in the airline when it was read; null when the planner didn''t know it (set to null if that aircraft is removed). fleet_checks() matches by registration as the planner stands';
comment on column public.game_fleet.registration is 'The registration as the game shows it, in capitals, e.g. N003AW';
comment on column public.game_fleet.type_name is 'The game''s name for the aircraft''s model, e.g. Airbus A321NEO Light';
comment on column public.game_fleet.nickname is 'The aircraft''s nickname in the game; null when it has none';
comment on column public.game_fleet.location_from is 'Where it is: the airport it''s at on the ground, or the airport it left when flying (then location_to is set)';
comment on column public.game_fleet.location_to is 'Where it''s flying to; null on the ground. A blank location on the page is an aircraft between flights, not an idle one';
comment on column public.game_fleet.flight is 'The flight it''s on, as the game writes it (AW 1003); null on the ground';
comment on column public.game_fleet.age_years is 'Its age in years, as the game rounds it';
comment on column public.game_fleet.condition_pct is 'Its condition, %, as the game shows it';
comment on column public.game_fleet.maintenance_pct is 'Its maintenance ratio, %, as the game shows it: under settings.maintenance_min_pct (100) the condition falls';
comment on column public.game_fleet.seats_y is 'Economy seats as fitted (the Y of Y/C/F)';
comment on column public.game_fleet.seats_c is 'Business seats as fitted (the C of Y/C/F)';
comment on column public.game_fleet.seats_f is 'First-class seats as fitted (the F of Y/C/F)';
comment on column public.game_fleet.pilots is 'Whether it has pilots (the game''s yes or no)';
comment on column public.game_fleet.owned is 'Whether we own it (yes) or lease it (no)';
comment on column public.game_fleet.contract_status is 'Its contract''s state as the game words it, e.g. active';
comment on column public.game_fleet.fleet_game_id is 'The game''s id of the fleet it was in (/app/fleets/<id>; Gitesh keeps one per hub); null for the Default fleet';
comment on column public.game_fleet.fleet_name is 'The name of the fleet it was in, e.g. JFK, or Default';
comment on column public.game_fleet.captured_at is 'When the page this row came from was captured (the latest of the day wins)';
comment on table public.game_capture_raw is 'Every page the capture sent, as rows of cells before parsing (a fleet page, since 22 Oct, as the capture read it: its fleet, the airline''s fleets and its aircraft), with its world and airline, and its check as it arrived (verdict, #21). Kept 14 days: the 10:20 UTC clean-up (private.job_cleanup, #13 pull request 7) deletes older pages. Written by capture_ingest(). Read by private.capture_page(), completeness (private.capture_day_complete), capture_status() and system_status() (each airline''s latest verdicts), fleet_checks() (whether every fleet page came in ok) and the planner''s Capture board.';
comment on column public.game_capture_raw.kind is 'statement, events, loads, pnl, balance, fleet (since 22 Oct: one fleet page) or html';
comment on column public.game_capture_raw.rows is 'The page''s table rows, each a list of cell texts; for a fleet page (since 22 Oct) the page as Capture all airlines read it: {run, page, of, fleet: {id, name}, fleets: [{id, name, aircraft}], aircraft: [...]}, or error in place of aircraft when it didn''t read';
comment on column public.game_capture_raw.verdict is 'The page''s check as it arrived (#21): ok, short (fewer rows than expected; a fleet page with no aircraft rows) or broken (didn''t read, or a balance sheet without the cash account); null for page inspection (html) and pages stored before 14 Oct''s checks';
comment on column public.game_capture_raw.verdict_facts is 'The numbers behind the verdict (#21): read (rows the reader took), and per kind scheduled and share (loads), median_lines and nights (statement), cash (balance), fleet, fleet_id, page, of and listed (fleet), the limit used, or the error';
comment on function private.capture_fleet(bigint) is 'Reads one stored fleet page (game_capture_raw kind fleet, since 22 Oct; spec docs/specs/2026-10-22-fleet-capture.md) into game_fleet: each aircraft on it, matched to the planner''s aircraft by registration within the airline, for the page''s capture day, the latest capture of the day winning. Raises an error, writing nothing, when the page didn''t read (its error, no aircraft list, or a row without its registration), which judges it broken. Answers how many aircraft it read. No check of its own.';
comment on function public.capture_ingest(text, text, text, text, jsonb) is 'Entry point for the in-game capture. Checks the capture key, which belongs to one world; finds the airline by the game''s ID or, from older userscripts, by name, and refuses one outside the key''s world; keeps the raw page (the 10:20 UTC clean-up deletes it after 14 days), parses it (private.capture_store, private.capture_page): bank statement into game_flights and game_payments, loads into game_flights, and since 22 Oct a fleet page (kind fleet, Capture all airlines 1.6) into game_fleet; and checks it (#21: the verdict under verdict). After the loads page, rows holds the capture panel''s words (what was read, and the airline''s verdict: "all good" or what came in short or broken) and count the rows read. Answers with the capture day and whether it is complete; the page that completes the world''s capture for the day also takes the daily snapshot (airline_days, route_days) and answers with it. Fleet pages take no part in completeness or the snapshot.';
comment on function private.capture_page(bigint) is 'Parses one stored capture page into the capture tables, using the page''s own capture time throughout: statement lines into game_statement, folded into game_flights and game_payments; events into game_events (with due_at where known); loads into game_flights; the income statement and balance sheet into game_pnl and game_balance (with capture_day), each row''s figures and capture time from the same capture, the latest (#13 pull request 6); since 22 Oct a fleet page into game_fleet (private.capture_fleet()). Then money and loads are matched, and since 22 Oct, after a statement or loads page, each captured flight of the world still without them gets its route and aircraft (private.fill_flight_links()).';
comment on function private.capture_expect(bigint) is 'What to expect of one stored capture page, from what the database knows at the page''s moment (#21). Loads: scheduled, the airline''s flights departing in the page''s window (the game''s -24h: the 24 hours before the capture), from its flight legs and their UTC weekdays, each rotation from the day after it launched, and a leg with an aircraft only once that aircraft has flown (its registration named by the airline''s captured loads before the page; since 15 Oct, as a new aircraft can start flying days after it''s filed). Statement: median_lines, the median of the lines on the airline''s latest statement page on each of up to 7 earlier capture days, and nights, how many. Fleet (since 22 Oct): the fleet''s name and id, which page of how many, and listed, the aircraft the airline''s fleet list gave it. Other kinds: nothing.';
comment on function private.capture_judge(text, integer, text, boolean, jsonb, numeric, numeric) is 'The verdict on one capture page (#21), from what was read and what was expected; reads no table. Broken: the page didn''t read (p_error), or a balance sheet without the cash account (2800). Short: loads fewer than p_loads_min of the flights scheduled; a statement with no lines, or fewer than p_statement_min of the recent median; events or an income statement with no rows; a fleet page (since 22 Oct) with no aircraft rows, named by its fleet ("fleet JFK"). Otherwise ok. Answers {verdict, note (in words), facts}; null for a kind it doesn''t judge (html).';
comment on function private.capture_check(bigint, jsonb, jsonb) is 'Judges one stored capture page and keeps the verdict on it (game_capture_raw.verdict, verdict_note, verdict_facts; #21), fleet pages included since 22 Oct. p_parse is private.capture_page()''s answer (its rows read) or the parse error; p_expect what to expect (private.capture_expect() when null; the tests give their own). The limits are settings: capture_loads_min_share and capture_statement_min_share. Answers the verdict with its facts; null for page inspection (html).';
comment on function private.capture_airline_verdict(bigint, timestamptz) is 'An airline''s capture as at a moment (#21): the latest page of each kind in that moment''s capture day (10:00 to 10:00 UTC) up to the moment, with its verdict, and the airline''s verdict: broken if any page is, short if any is or a kind wasn''t captured, ok when every page is; null when no page was judged (stored before the checks). words: "all good", or what came in short or broken. Since 22 Oct also the day''s fleet pages, when it has some (the latest page of each fleet): a short or broken one makes the airline short or broken and is named in words, and pages.fleet gives their verdict, note ("fleet 3 pages, 21 aircraft", or what came in short or broken), latest time, pages, ok pages and aircraft read. An airline with no fleet pages is judged as before.';
comment on function private.fig_capture_status(bigint, timestamptz) is 'The captured figures (#19): the capture board''s document (captureBoard), each airline''s pages today and yesterday (UTC), flights by departure date, what is missing today and its status; since #21 also its latest page (last_at) and that capture''s verdicts (private.capture_airline_verdict(): verdict, verdict_words, verdict_at, verdict_day and each kind''s under verdicts); since 22 Oct its fleet pages count as pages for last_at, and fleet gives that capture day''s fleet pages (verdicts.fleet), only when it has some. See capture_status().';
comment on function public.capture_status(bigint, timestamptz) is 'What the capture collected for each of our airlines in a world (the default world when null; decision #19, design §8; the old planner''s captureBoard): for today and yesterday (UTC dates of p_as_of), when each page kind (loads, statement, events, pnl, balance) last came, how many flights the loads page held for each date (flight numbers, by departure date as the game lists them), which kinds are missing today, and complete, missing or not captured; each airline''s latest verdicts (#21), and since 22 Oct its fleet pages (fleet: their verdict, note, time, pages, ok pages and aircraft) when that capture day has some. Moments in UTC. Staff only; runs as owner and checks the caller itself.';
comment on function private.fig_fleet_checks(bigint, timestamptz) is 'The captured figures (#19): builds fleet_checks()''s document with no check of its own. See fleet_checks().';
comment on function public.fleet_checks(bigint, timestamptz) is 'The fleet checks (spec docs/specs/2026-10-22-fleet-capture.md §2; manual §7), in a world (the default when null), as of p_as_of (now by default), from the latest night''s game_fleet for our airlines (night: the latest capture day any of them has, captured by the moment). problems, worst first (maintenance, crew, cabin, not in the planner, not in the game; then by airline and registration), each with its kind, airline, registration, base (the planner''s, else the fleet''s), aircraft and words: maintenance, the game''s maintenance under settings.maintenance_min_pct (100; an airline''s own where it has one), with the condition beside it ("N003AW (JFK): maintenance 0.0%, condition 83%"); crew, pilots no; cabin, seats Y/C/F that don''t match the aircraft''s cabin in the planner (aircraft.cabin_config_id, cabin_configs'' economy and business seats, first class 0), or no cabin in the planner; not_in_planner, a registration on the game''s fleet pages that no aircraft row of the airline has; not_in_game, an active aircraft of ours missing from that night''s fleet pages, only when every fleet page of its airline''s latest run that night came in ok. counts: each kind''s and problems in all. airlines: each of ours with its maintenance limit, its latest run''s pages (read, ok, expected, all_ok), when its fleet was read and its aircraft that night (registration, planner aircraft, base, fleet, type, nickname, location, flight, age, condition, maintenance, seats, pilots, owned, contract, captured_at and its problems). Staff only, read with GET; runs as owner with its own 30 second limit, as the other figures.';

select set_config('equinox.actor', '', true), set_config('equinox.actor_detail', '', true);

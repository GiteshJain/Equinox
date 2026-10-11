-- The daily history and the world-scan tables (decision #13, build pull request 6).
-- Design: docs/design/2026-10-09-data-model.md (§2, §3.9, §3.10, §5, §6, §7, §9 step 4, §10 row 6, §11 choice 2).
-- Spec: docs/specs/2026-10-11-history.md.
--
-- Adds and changes; removes nothing. The two things that need a removal (signed-in accounts' leftover write access to
-- the three old scan tables, and the scan schedules' old copy in game_scan_airlines.flights) are in
-- 20261011120100_history_removals.sql, which Gitesh runs after this one (manual §1).
--   1. two captures on one UTC date: game_balance and game_pnl take each row's figures and its capture time from the
--      same, latest capture; rows the old rule left with the first capture's time get the time of the page that
--      wrote them;
--   2. the daily history (§3.10): airline_days and route_days, staff read only, not in the change log (§6);
--   3. the world scans renamed and split (§3.9): game_scans, game_scan_airlines (totals), game_scan_schedules (each
--      airline's schedule), game_scan_airports, each with its world (and airline); every airline a scan saw becomes an
--      airlines row by game ID; the summaries kept for good (§11 choice 2): scan_airline_airports and
--      scan_airline_markets;
--   4. the snapshot (§7): private.take_snapshot(world, day), taken by the capture (private.capture_store(), which
--      capture_ingest() calls with the page's time) after the page that completes a world's capture for the day; one
--      job_runs row each;
--   5. ingest_snapshot() writes the new tables (and takes the weekly report's market summaries, kind markets), and
--      export_for_report()'s scan kinds read them, with the same answers as before;
--   6. the backfill (§9 step 4): airline_days from 29 Sep (cash as stored, then from game_balance), route_days and the
--      day's flows from 6 Oct, and the airport summaries of every scan already stored;
--   7. access and descriptions.
-- Apply it when no capture is running.

select set_config('equinox.actor', 'migration', true),
       set_config('equinox.actor_detail', '20261011120000_history', true),
       set_config('equinox.change_log', 'off', true);

-- ============================================================ 1. two captures on one UTC date (found by pull request 3)
-- game_balance and game_pnl are keyed by airline, UTC date and account (or line). A second capture the same UTC date
-- overwrote the figures but kept the first capture's captured_at, so the cash forecast and capture_cash timed the second
-- capture's cash by the first capture's clock. Now a row's figures, its time and its capture day always come from the
-- same capture: the latest (a page replayed out of order doesn't overwrite a newer one). The rest of the function is
-- as pull request 3 left it.
create or replace function private.capture_page(p_raw_id bigint)
 returns jsonb
 language plpgsql
 set search_path to ''
as $function$
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
$function$;

-- The rows the old rule left with the first capture's time: each takes the time (and capture day) of the latest kept
-- page of its airline and UTC date that holds it, when that page holds it with the stored figures (the page that wrote
-- them). Figures never change here; a row no kept page holds stays as it is.
do $repair$
declare n_bal int; n_pnl int; n_bal_odd int; n_pnl_odd int;
begin
  create temporary table t_repair_bal on commit drop as
  with pages as (
    select r.airline_id, r.captured_at, (r.captured_at at time zone 'UTC')::date as d, x.account, x.amount
      from public.game_capture_raw r
      cross join lateral jsonb_array_elements(case when jsonb_typeof(r.rows) = 'array' then r.rows else '[]'::jsonb end) e(row_)
      cross join lateral (select array(select jsonb_array_elements_text(case when jsonb_typeof(e.row_) = 'array' then e.row_ else '[]'::jsonb end)) as c) cc
      cross join lateral (values
        (case when array_length(cc.c, 1) >= 3 and cc.c[1] ~ '^\d{3,4}$' then cc.c[1] || ' ' || cc.c[2] end, public.as_num(cc.c[3])),
        (case when array_length(cc.c, 1) >= 6 and cc.c[4] ~ '^\d{3,4}$' then cc.c[4] || ' ' || cc.c[5] end, public.as_num(cc.c[6]))) x(account, amount)
     where r.kind = 'balance' and x.account is not null)
  select distinct on (p.airline_id, p.d, p.account) p.airline_id, p.d, p.account, p.amount, p.captured_at
    from pages p order by p.airline_id, p.d, p.account, p.captured_at desc;
  update public.game_balance b set captured_at = l.captured_at, capture_day = private.capture_day(b.world_id, l.captured_at)
    from t_repair_bal l
   where l.airline_id = b.airline_id and l.d = b.captured_on and l.account = b.account
     and l.amount is not distinct from b.amount and l.captured_at > b.captured_at;
  get diagnostics n_bal = row_count;
  select count(*) into n_bal_odd from t_repair_bal l join public.game_balance b
      on l.airline_id = b.airline_id and l.d = b.captured_on and l.account = b.account
   where l.amount is distinct from b.amount;

  create temporary table t_repair_pnl on commit drop as
  with pages as (
    select r.airline_id, r.captured_at, (r.captured_at at time zone 'UTC')::date as d, cc.c[1] as line,
           public.as_num(cc.c[2]) as current_p, public.as_num(cc.c[3]) as last_p, public.as_num(cc.c[array_length(cc.c, 1)]) as total_p
      from public.game_capture_raw r
      cross join lateral jsonb_array_elements(case when jsonb_typeof(r.rows) = 'array' then r.rows else '[]'::jsonb end) e(row_)
      cross join lateral (select array(select jsonb_array_elements_text(case when jsonb_typeof(e.row_) = 'array' then e.row_ else '[]'::jsonb end)) as c) cc
     where r.kind = 'pnl' and array_length(cc.c, 1) >= 3 and cc.c[2] ~ 'AS\$')
  select distinct on (p.airline_id, p.d, p.line) p.airline_id, p.d, p.line, p.current_p, p.last_p, p.total_p, p.captured_at
    from pages p order by p.airline_id, p.d, p.line, p.captured_at desc;
  update public.game_pnl g set captured_at = l.captured_at, capture_day = private.capture_day(g.world_id, l.captured_at)
    from t_repair_pnl l
   where l.airline_id = g.airline_id and l.d = g.captured_on and l.line = g.line
     and (l.current_p, l.last_p, l.total_p) is not distinct from (g.current_p, g.last_p, g.total_p) and l.captured_at > g.captured_at;
  get diagnostics n_pnl = row_count;
  select count(*) into n_pnl_odd from t_repair_pnl l join public.game_pnl g
      on l.airline_id = g.airline_id and l.d = g.captured_on and l.line = g.line
   where (l.current_p, l.last_p, l.total_p) is distinct from (g.current_p, g.last_p, g.total_p);
  raise notice 'two captures on one UTC date: % balance-sheet and % income-statement rows now carry their figures'' own capture time (% and % rows whose latest page holds other figures left as they were)',
    n_bal, n_pnl, n_bal_odd, n_pnl_odd;
end
$repair$;

-- ============================================================ 2. the daily history (§3.10)
-- One row per airline per capture day (§2: the evening it was taken, 10:00 to 10:00 UTC). Point-in-time figures are
-- fixed when the snapshot is taken; the day's flows are for the UTC day of the same date, recomputed for two days after.
create table public.airline_days (
  world_id bigint not null references public.worlds (id),
  airline_id bigint not null,
  day date not null,
  complete boolean not null default false,
  source text not null check (source in ('capture', 'fallback', 'backfill')),
  taken_at timestamptz not null,
  aircraft_by_type jsonb,
  aircraft_total int,
  on_order int,
  weekly_departures int,
  weekly_seats int,
  destinations int,
  cash numeric(14,2),
  fixed_next7 numeric(14,2),
  cash_at timestamptz,
  flights_flown int,
  passengers int,
  seats_flown int,
  load_pct numeric(5,1),
  eco_load_pct numeric(5,1),
  revenue numeric(14,2),
  flight_costs numeric(14,2),
  flight_profit numeric(14,2),
  leases_paid numeric(14,2),
  salaries_paid numeric(14,2),
  purchases_paid numeric(14,2),
  primary key (airline_id, day),
  constraint airline_days_airline_fkey foreign key (airline_id, world_id) references public.airlines (id, world_id)
);
create index airline_days_world_day_idx on public.airline_days (world_id, day);

-- Per route, direction and UTC day (a flight's day is the UTC date it departs, §2)
create table public.route_days (
  world_id bigint not null references public.worlds (id),
  airline_id bigint not null,
  route_id bigint,
  origin_code text not null,
  dest_code text not null,
  day date not null,
  flights int not null,
  passengers int,
  seats int,
  revenue numeric(14,2),
  costs numeric(14,2),
  profit numeric(14,2),
  eco_fare_avg numeric(14,2),
  primary key (airline_id, origin_code, dest_code, day),
  constraint route_days_airline_fkey foreign key (airline_id, world_id) references public.airlines (id, world_id),
  -- a route the planner removes later keeps its history by its airports
  constraint route_days_route_fkey foreign key (route_id, world_id) references public.routes (id, world_id) on delete set null (route_id)
);
create index route_days_world_day_idx on public.route_days (world_id, day);
create index route_days_route_id_idx on public.route_days (route_id);

-- ============================================================ 3. the world scans, renamed and split (§3.9)
-- 3a. game_snapshots -> game_scans, with its world (every scan so far is Gander's)
alter table public.game_snapshots rename to game_scans;
do $rename$
declare t text; c record; s text;
begin
  -- the constraints (and their indexes) and the id's sequence follow the tables' new names
  foreach t in array array['game_scans', 'game_snapshot_airlines', 'game_snapshot_airports'] loop
    for c in select con.conname from pg_catalog.pg_constraint con
              where con.conrelid = ('public.' || t)::regclass and con.conname like 'game\_snapshot%' loop
      execute format('alter table public.%I rename constraint %I to %I', t, c.conname,
                     replace(regexp_replace(c.conname, '^game_snapshots?(_airlines|_airports)?_(.*)$',
                                            'game_scan' || case when t = 'game_scans' then 's' else '' end || '\1_\2'),
                             'snapshot_id', 'scan_id'));
    end loop;
  end loop;
  s := pg_catalog.pg_get_serial_sequence('public.game_scans', 'id');
  if s is not null and s <> 'public.game_scans_id_seq' then execute format('alter sequence %s rename to game_scans_id_seq', s); end if;
end
$rename$;
alter table public.game_scans add column world_id bigint;
update public.game_scans set world_id = (select w.id from public.worlds w where w.is_default);
alter table public.game_scans alter column world_id set not null,
  add constraint game_scans_world_fkey foreign key (world_id) references public.worlds (id),
  add constraint game_scans_id_world_key unique (id, world_id);
create index game_scans_world_taken_idx on public.game_scans (world_id, taken_at);

-- 3b. every airline a scan saw becomes an airlines row by game ID (§3.9), named as the latest scan saw it: the
--     airlines scanned, and those stationed at a scanned airport. Ours are there already and stay as they are.
insert into public.airlines (world_id, game_id, game_name)
select distinct on (x.game_id) s.world_id, x.game_id, nullif(btrim(x.name), '')
  from (select a.snapshot_id as scan_id, a.enterprise_id as game_id, a.name, 1 as pri from public.game_snapshot_airlines a
        union all
        select p.snapshot_id, (st ->> 'enterprise_id')::int, st ->> 'name', 2 from public.game_snapshot_airports p
          cross join lateral jsonb_array_elements(case when jsonb_typeof(p.stations) = 'array' then p.stations else '[]'::jsonb end) st
         where (st ->> 'enterprise_id') ~ '^\d{1,9}$') x
  join public.game_scans s on s.id = x.scan_id
 order by x.game_id, s.taken_at desc, x.pri
on conflict (world_id, game_id) do nothing;

-- 3c. game_snapshot_airlines -> game_scan_airlines: each airline's totals in a scan, with its world and airline
alter table public.game_snapshot_airlines rename to game_scan_airlines;
alter table public.game_scan_airlines rename column snapshot_id to scan_id;
alter table public.game_scan_airlines add column world_id bigint, add column airline_id bigint;
update public.game_scan_airlines a set world_id = s.world_id, airline_id = al.id
  from public.game_scans s, public.airlines al
 where s.id = a.scan_id and al.world_id = s.world_id and al.game_id = a.enterprise_id;
alter table public.game_scan_airlines alter column world_id set not null, alter column airline_id set not null,
  add constraint game_scan_airlines_scan_world_fkey foreign key (scan_id, world_id) references public.game_scans (id, world_id) on delete cascade,
  add constraint game_scan_airlines_airline_fkey foreign key (airline_id, world_id) references public.airlines (id, world_id),
  add constraint game_scan_airlines_scan_airline_key unique (scan_id, airline_id);
create index game_scan_airlines_airline_scan_idx on public.game_scan_airlines (airline_id, scan_id);

-- 3d. game_scan_schedules: each airline's full schedule in a scan, moved out of the totals (archived after a month,
--     the totals kept for good). The old copy (game_scan_airlines.flights) goes in the removal file.
create table public.game_scan_schedules (
  scan_id bigint not null,
  world_id bigint not null,
  airline_id bigint not null,
  flights jsonb not null default '[]'::jsonb,
  primary key (scan_id, airline_id),
  constraint game_scan_schedules_scan_world_fkey foreign key (scan_id, world_id) references public.game_scans (id, world_id) on delete cascade,
  constraint game_scan_schedules_airline_fkey foreign key (airline_id, world_id) references public.airlines (id, world_id)
);
create index game_scan_schedules_airline_scan_idx on public.game_scan_schedules (airline_id, scan_id);
insert into public.game_scan_schedules (scan_id, world_id, airline_id, flights)
select a.scan_id, a.world_id, a.airline_id, a.flights from public.game_scan_airlines a;

-- 3e. game_snapshot_airports -> game_scan_airports, with its world. The world is added as a constant default and the
--     default then dropped, so the table isn't rewritten and its rows keep the order export_for_report() lists them in.
alter table public.game_snapshot_airports rename to game_scan_airports;
alter table public.game_scan_airports rename column snapshot_id to scan_id;
alter table public.game_scan_airports rename column code to airport_code;
alter table public.game_scan_airports rename column airport_id to game_airport_id;
do $world$
begin
  execute format('alter table public.game_scan_airports add column world_id bigint not null default %s',
                 (select w.id from public.worlds w where w.is_default));
end
$world$;
alter table public.game_scan_airports alter column world_id drop default,
  add constraint game_scan_airports_scan_world_fkey foreign key (scan_id, world_id) references public.game_scans (id, world_id) on delete cascade;

-- 3f. the summaries kept for good (§11 choice 2)
create table public.scan_airline_airports (
  scan_id bigint not null,
  world_id bigint not null,
  airline_id bigint not null,
  airport_code text not null,
  weekly_departures int not null,
  destinations int not null,
  primary key (scan_id, airline_id, airport_code),
  constraint scan_airline_airports_scan_world_fkey foreign key (scan_id, world_id) references public.game_scans (id, world_id) on delete cascade,
  constraint scan_airline_airports_airline_fkey foreign key (airline_id, world_id) references public.airlines (id, world_id)
);
create index scan_airline_airports_airline_scan_idx on public.scan_airline_airports (airline_id, scan_id);

create table public.scan_airline_markets (
  scan_id bigint not null,
  world_id bigint not null,
  airline_id bigint not null,
  market text not null,
  weekly_departures int not null,
  city_pairs int not null,
  primary key (scan_id, airline_id, market),
  constraint scan_airline_markets_scan_world_fkey foreign key (scan_id, world_id) references public.game_scans (id, world_id) on delete cascade,
  constraint scan_airline_markets_airline_fkey foreign key (airline_id, world_id) references public.airlines (id, world_id)
);
create index scan_airline_markets_airline_scan_idx on public.scan_airline_markets (airline_id, scan_id);

-- ============================================================ 4. the snapshot (§7)
-- The history covers the active airlines of our groups in a world, as completeness counts them.

-- The fleet at a moment, per airline (design §7, §9 step 4): an aircraft is flying from its arrival in the game
-- (delivery_at; one with no delivery record from the start) until it is retired, unless it is still marked on order;
-- it is on order from its order date (or always, with none) until then. With the moment now, that is exactly what
-- aircraft.status says: active and delivered are flying, on_order on order.
create or replace function private.history_fleet(p_world_id bigint, p_at timestamptz)
 returns table (airline_id bigint, aircraft_by_type jsonb, aircraft_total int, on_order int)
 language sql
 stable
 set search_path to ''
as $function$
  with ours as (
    select a.id from public.airlines a join public.groups g on g.id = a.group_id and g.world_id = a.world_id
     where a.world_id = p_world_id and a.active and g.kind = 'ours'),
  ac as (
    select x.airline_id, coalesce(t.name, '(no type)') as type_name, x.ordered_on, x.status, x.delivery_at,
           x.status = 'retired' and (x.retired_on is null or x.retired_on <= (p_at at time zone 'UTC')::date) as gone
      from public.aircraft x left join public.aircraft_types t on t.id = x.aircraft_type_id
     where x.world_id = p_world_id),
  st as (
    select ac.airline_id, ac.type_name,
           not ac.gone and ac.status <> 'on_order' and (ac.delivery_at is null or ac.delivery_at <= p_at) as flying,
           not ac.gone and (ac.status = 'on_order' or ac.delivery_at > p_at)
             and (ac.ordered_on is null or ac.ordered_on <= (p_at at time zone 'UTC')::date) as ordered
      from ac),
  by_type as (
    select s.airline_id, s.type_name, count(*)::int as n from st s where s.flying group by s.airline_id, s.type_name)
  select o.id,
         coalesce((select jsonb_object_agg(b.type_name, b.n) from by_type b where b.airline_id = o.id), '{}'::jsonb),
         (select count(*)::int from st s where s.airline_id = o.id and s.flying),
         (select count(*)::int from st s where s.airline_id = o.id and s.ordered)
    from ours o
$function$;

-- The weekly schedule as it stood on a day, per airline: the legs of every rotation launched by then (one with no
-- launch date from the start), assuming nothing was dropped (§9 step 4). Seats from each leg's aircraft's cabin, or its
-- type's maximum (§4); destinations are the routes' far ends.
create or replace function private.history_schedule(p_world_id bigint, p_day date)
 returns table (airline_id bigint, weekly_departures int, weekly_seats int, destinations int)
 language sql
 stable
 set search_path to ''
as $function$
  select r.airline_id, sum(cardinality(l.days_utc))::int,
         sum(cardinality(l.days_utc) * coalesce(c.seats, t.seats_max, 0))::int,
         count(distinct ro.dest_code)::int
    from public.rotations r
    join public.routes ro on ro.id = r.route_id
    join public.flight_legs l on l.rotation_id = r.id
    left join public.aircraft a on a.id = l.aircraft_id
    left join public.cabin_configs c on c.id = a.cabin_config_id
    left join public.aircraft_types t on t.id = a.aircraft_type_id
   where r.world_id = p_world_id and (r.launched_on is null or r.launched_on <= p_day)
   group by r.airline_id
$function$;

-- Cash on a capture day, per airline (§7): the latest balance of account 2800 that capture day, up to the moment, with
-- the payments the events page lists for the 7 days after it (as capture_cash and the planner work them out); with no
-- balance that day, the figures typed by hand or kept from before the capture (cash_entries, by the planner's date).
create or replace function private.history_cash(p_world_id bigint, p_day date, p_at timestamptz)
 returns table (airline_id bigint, cash numeric, fixed_next7 numeric, cash_at timestamptz)
 language sql
 stable
 set search_path to ''
as $function$
  with ours as (
    select a.id from public.airlines a join public.groups g on g.id = a.group_id and g.world_id = a.world_id
     where a.world_id = p_world_id and a.active and g.kind = 'ours'),
  bal as (
    select distinct on (b.airline_id) b.airline_id, b.amount, b.captured_at
      from public.game_balance b
     where b.world_id = p_world_id and b.capture_day = p_day and b.account like '2800%' and b.amount is not null
       and b.captured_at <= p_at
     order by b.airline_id, b.captured_at desc)
  select o.id,
         case when bal.airline_id is not null then bal.amount else ce.cash end,
         case when bal.airline_id is not null
              then (select sum(e.debit) from public.game_events e
                     where e.airline_id = o.id and e.debit > 0 and e.due_at > bal.captured_at
                       and e.due_at <= bal.captured_at + interval '7 days')
              else ce.fixed_next7 end,
         bal.captured_at
    from ours o
    left join bal on bal.airline_id = o.id
    left join public.cash_entries ce on ce.airline_id = o.id and ce.day = p_day
$function$;

-- The flows for a span of UTC days (§7): route_days replaced for those days, and each airline_days row of those days
-- given its flights, passengers, seats, loads, money and payments. A flight is a game_flights row with its loads or
-- with passenger income (as game_ops_recent counts them); its day is the UTC date of dep_at (the game's date where the
-- airports' offsets weren't known). The money is every statement block of the day, the payments by when they posted.
create or replace function private.history_flows(p_world_id bigint, p_from date, p_to date)
 returns jsonb
 language plpgsql
 set search_path to ''
as $function$
declare n_routes int := 0; n_days int := 0;
begin
  if p_from is null or p_to is null or p_to < p_from then
    return jsonb_build_object('route_days', 0, 'airline_days', 0);
  end if;
  if to_regclass('pg_temp.t_history_rows') is null then
    create temporary table t_history_rows (airline_id bigint, route_id bigint, origin_code text, dest_code text, day date,
      is_flight boolean, has_loads boolean, pax int, seats int, eco_pax int, eco_seats int, eco_fare numeric, income numeric,
      costs numeric) on commit drop;
  end if;
  truncate pg_temp.t_history_rows;
  insert into pg_temp.t_history_rows
  select f.airline_id, f.route_id, nullif(f.origin_code, ''), nullif(f.dest_code, ''),
         coalesce((f.dep_at at time zone 'UTC')::date, f.game_date),
         f.flight_no is not null or f.pax_income is not null, f.flight_no is not null,
         case when f.flight_no is not null then coalesce(f.eco_pax, 0) + coalesce(f.bus_pax, 0) + coalesce(f.fst_pax, 0)
              else f.statement_pax end,
         case when f.flight_no is not null then coalesce(f.eco_seats, 0) + coalesce(f.bus_seats, 0) + coalesce(f.fst_seats, 0) end,
         case when f.flight_no is not null then f.eco_pax end, case when f.flight_no is not null then f.eco_seats end,
         f.eco_fare, f.income_total, f.cost_total
    from public.game_flights f
   where f.world_id = p_world_id
     and f.dep_at >= (p_from::timestamp at time zone 'UTC') and f.dep_at < ((p_to + 1)::timestamp at time zone 'UTC')
  union all
  select f.airline_id, f.route_id, nullif(f.origin_code, ''), nullif(f.dest_code, ''), f.game_date, true, true,
         coalesce(f.eco_pax, 0) + coalesce(f.bus_pax, 0) + coalesce(f.fst_pax, 0),
         coalesce(f.eco_seats, 0) + coalesce(f.bus_seats, 0) + coalesce(f.fst_seats, 0),
         f.eco_pax, f.eco_seats, f.eco_fare, f.income_total, f.cost_total
    from public.game_flights f
   where f.world_id = p_world_id and f.dep_at is null and f.flight_no is not null and f.game_date between p_from and p_to;

  delete from public.route_days r where r.world_id = p_world_id and r.day between p_from and p_to;
  insert into public.route_days (world_id, airline_id, route_id, origin_code, dest_code, day, flights, passengers, seats,
                                 revenue, costs, profit, eco_fare_avg)
  select p_world_id, x.airline_id, max(x.route_id), x.origin_code, x.dest_code, x.day, count(*)::int,
         sum(x.pax)::int, sum(x.seats)::int,
         coalesce(sum(x.income), 0), coalesce(sum(x.costs), 0), coalesce(sum(x.income), 0) - coalesce(sum(x.costs), 0),
         round(coalesce(sum(x.eco_fare * x.eco_pax) filter (where x.eco_pax > 0)
                          / nullif(sum(x.eco_pax) filter (where x.eco_pax > 0 and x.eco_fare is not null), 0),
                        avg(x.eco_fare)), 2)
    from pg_temp.t_history_rows x
   where x.is_flight and x.origin_code is not null and x.dest_code is not null
   group by x.airline_id, x.origin_code, x.dest_code, x.day;
  get diagnostics n_routes = row_count;

  update public.airline_days a
     set flights_flown = coalesce(v.flights, 0), passengers = coalesce(v.pax, 0), seats_flown = coalesce(v.seats, 0),
         load_pct = round(100.0 * v.loads_pax / nullif(v.seats, 0), 1),
         eco_load_pct = round(100.0 * v.eco_pax / nullif(v.eco_seats, 0), 1),
         revenue = coalesce(v.income, 0), flight_costs = coalesce(v.costs, 0),
         flight_profit = coalesce(v.income, 0) - coalesce(v.costs, 0),
         leases_paid = coalesce(p.leases, 0), salaries_paid = coalesce(p.salaries, 0), purchases_paid = coalesce(p.purchases, 0)
    from public.airline_days d
    left join lateral (
      select count(*) filter (where x.is_flight) as flights,
             sum(x.pax) filter (where x.is_flight) as pax,
             sum(x.seats) filter (where x.is_flight and x.has_loads) as seats,
             sum(x.pax) filter (where x.is_flight and x.has_loads) as loads_pax,
             sum(x.eco_pax) filter (where x.is_flight and x.has_loads) as eco_pax,
             sum(x.eco_seats) filter (where x.is_flight and x.has_loads) as eco_seats,
             sum(x.income) as income, sum(x.costs) as costs
        from pg_temp.t_history_rows x where x.airline_id = d.airline_id and x.day = d.day) v on true
    left join lateral (
      select sum(case when y.side = 'C' then -y.amount else y.amount end) filter (where y.kind = 'lease') as leases,
             sum(case when y.side = 'C' then -y.amount else y.amount end) filter (where y.kind = 'salaries') as salaries,
             sum(case when y.side = 'C' then -y.amount else y.amount end)
               filter (where y.kind in ('purchase', 'deposit', 'cabin', 'refit')) as purchases
        from public.game_payments y
       where y.airline_id = d.airline_id
         and y.paid_at >= (d.day::timestamp at time zone 'UTC') and y.paid_at < ((d.day + 1)::timestamp at time zone 'UTC')) p on true
   where a.airline_id = d.airline_id and a.day = d.day and d.world_id = p_world_id and d.day between p_from and p_to;
  get diagnostics n_days = row_count;
  truncate pg_temp.t_history_rows;
  return jsonb_build_object('route_days', n_routes, 'airline_days', n_days);
end
$function$;

-- The daily snapshot (§7) of a world's capture day: point-in-time figures (fleet and schedule from the tables, cash
-- from the day's latest balance) as at p_at (default now), into airline_days for each of our active airlines; then the
-- flows of that UTC day and the two before (p_flows). A later snapshot of the same day replaces the point-in-time
-- figures, except that a fallback or backfill never replaces one taken from a complete capture.
create or replace function private.take_snapshot(p_world_id bigint, p_day date, p_at timestamptz default null,
                                                 p_source text default 'capture', p_flows boolean default true)
 returns jsonb
 language plpgsql
 set search_path to ''
as $function$
declare v_at timestamptz := coalesce(p_at, now()); v_complete boolean; n int; v_flows jsonb;
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
  if p_flows then v_flows := private.history_flows(p_world_id, p_day - 2, p_day); end if;
  return jsonb_build_object('day', p_day, 'source', p_source, 'complete', v_complete, 'at', v_at, 'airlines', n)
         || coalesce(v_flows, '{}'::jsonb);
end
$function$;

-- Whether a page at p_at completes a capture of the world for the day: every active airline of our groups has all five
-- pages between the day's start (or the last snapshot taken from a complete capture that day) and p_at. So the page
-- that completes the evening's capture takes the snapshot, the pages after it don't, and a second complete capture the
-- same day takes another.
create or replace function private.snapshot_due(p_world_id bigint, p_day date, p_at timestamptz)
 returns boolean
 language sql
 stable
 set search_path to ''
as $function$
  with ours as (
    select a.id from public.airlines a join public.groups g on g.id = a.group_id and g.world_id = a.world_id
     where a.world_id = p_world_id and a.active and g.kind = 'ours'),
  span as (
    select private.capture_day_start(p_world_id, p_day) as from_at,
           (select max(d.taken_at) from public.airline_days d
             where d.world_id = p_world_id and d.day = p_day and d.source = 'capture') as last_at)
  select exists (select 1 from ours)
     and not exists (
       select 1 from ours o, span
        where (select count(distinct r.kind) from public.game_capture_raw r
                where r.airline_id = o.id and r.kind in ('statement', 'events', 'pnl', 'balance', 'loads')
                  and r.captured_at >= span.from_at and r.captured_at < span.from_at + interval '1 day'
                  and (span.last_at is null or r.captured_at > span.last_at) and r.captured_at <= p_at) < 5)
$function$;

-- The capture stores and parses a page as before (pull request 3), then, when that page completes the world's capture
-- for the day, takes the snapshot (one job_runs row, ok or failed; a failure never loses the page). capture_ingest()
-- calls it with now(); the tests replay pages with their own times.
create or replace function private.capture_store(p_world_id bigint, p_airline text, p_kind text, p_page text, p_rows jsonb,
                                                 p_at timestamptz, p_loads_step boolean default true)
 returns jsonb
 language plpgsql
 set search_path to ''
as $function$
declare v_al bigint; v_name text; v_rid bigint; v_res jsonb; v_day date; v_complete boolean; v_snap jsonb;
  t0 timestamptz;
begin
  v_al := private.capture_find_airline(p_world_id, p_airline);
  if v_al is null then
    return jsonb_build_object('ok', false, 'error', 'not an airline of this capture key''s world: ' || coalesce(p_airline, '(none)'));
  end if;
  select coalesce(a.planner_name, a.public_name, a.game_name, a.game_id::text) into v_name from public.airlines a where a.id = v_al;
  insert into public.game_capture_raw (world_id, airline_id, airline, kind, page_url, rows, captured_at)
  values (p_world_id, v_al, v_name, p_kind, p_page, coalesce(p_rows, '[]'::jsonb), p_at)
  returning id into v_rid;
  if p_kind = 'html' then return jsonb_build_object('ok', true, 'kind', 'html', 'rows', 1, 'airline', v_name); end if;   -- page inspection: stored only
  begin
    v_res := private.capture_page(v_rid) || jsonb_build_object('airline', v_name);
    if p_kind = 'loads' and p_loads_step then v_res := v_res || private.apply_loads_from_capture(v_al); end if;
  exception when others then
    v_res := jsonb_build_object('ok', false, 'airline', v_name, 'error', 'parse: ' || sqlerrm, 'raw_id', v_rid);   -- the raw rows stay for inspection
  end;
  v_day := private.capture_day(p_world_id, p_at);
  v_complete := private.capture_day_complete(p_world_id, v_day);
  -- the daily snapshot, when this page completes the day's capture (design §7)
  if v_complete and p_kind in ('statement', 'events', 'pnl', 'balance', 'loads') and private.snapshot_due(p_world_id, v_day, p_at) then
    t0 := clock_timestamp();
    begin
      v_snap := private.take_snapshot(p_world_id, v_day, p_at, 'capture');
      insert into public.job_runs (job, world_id, started_at, finished_at, status, for_day, note, details)
      values ('snapshot', p_world_id, t0, clock_timestamp(), 'ok', v_day,
              format('capture complete: %s airline(s), %s route day(s)', v_snap ->> 'airlines', v_snap ->> 'route_days'), v_snap);
    exception when others then
      v_snap := jsonb_build_object('ok', false, 'error', sqlerrm);
      insert into public.job_runs (job, world_id, started_at, finished_at, status, for_day, note, details)
      values ('snapshot', p_world_id, t0, clock_timestamp(), 'failed', v_day, 'snapshot: ' || sqlerrm,
              jsonb_build_object('at', p_at, 'source', 'capture'));
    end;
  end if;
  return v_res || jsonb_build_object('capture_day', v_day, 'day_complete', v_complete)
         || case when v_snap is null then '{}'::jsonb else jsonb_build_object('snapshot', v_snap) end;
end
$function$;

-- ============================================================ 5. the scan's functions
-- The airlines row for an airline a scan saw, by its game ID, added when it's new (a rival's name kept as the game
-- shows it; ours stay as they are). Null without a game ID.
create or replace function private.scan_airline(p_world_id bigint, p_game_id int, p_name text)
 returns bigint
 language plpgsql
 set search_path to ''
as $function$
declare v_id bigint; v_name text := nullif(btrim(p_name), '');
begin
  if p_game_id is null then return null; end if;
  select a.id into v_id from public.airlines a where a.world_id = p_world_id and a.game_id = p_game_id;
  if v_id is null then
    insert into public.airlines (world_id, game_id, game_name) values (p_world_id, p_game_id, v_name)
    on conflict (world_id, game_id) do nothing
    returning id into v_id;
    if v_id is null then
      select a.id into v_id from public.airlines a where a.world_id = p_world_id and a.game_id = p_game_id;
    end if;
  elsif v_name is not null then
    update public.airlines a set game_name = v_name
     where a.id = v_id and a.game_name is distinct from v_name
       and not exists (select 1 from public.groups g where g.id = a.group_id and g.kind = 'ours');
  end if;
  return v_id;
end
$function$;

-- A scan's airport summaries (§3.9): per airline and airport, its weekly departures there and how many destinations
-- it flies to from there, from the airline's schedule in the scan (flights with no weekdays left out). Built again from
-- scratch; a scan whose schedules were archived keeps the summaries it has. Returns the rows written.
create or replace function private.scan_summarise(p_scan_id bigint)
 returns integer
 language plpgsql
 set search_path to ''
as $function$
declare n int := 0;
begin
  if not exists (select 1 from public.game_scan_schedules s where s.scan_id = p_scan_id) then return 0; end if;
  delete from public.scan_airline_airports where scan_id = p_scan_id;
  insert into public.scan_airline_airports (scan_id, world_id, airline_id, airport_code, weekly_departures, destinations)
  select s.scan_id, s.world_id, s.airline_id, f ->> 2,
         sum(length(regexp_replace(coalesce(f ->> 4, ''), '[^1-7]', '', 'g')))::int,
         count(distinct nullif(f ->> 3, ''))::int
    from public.game_scan_schedules s
    cross join lateral jsonb_array_elements(case when jsonb_typeof(s.flights) = 'array' then s.flights else '[]'::jsonb end) f
   where s.scan_id = p_scan_id and jsonb_typeof(f) = 'array' and coalesce(f ->> 2, '') <> ''
     and regexp_replace(coalesce(f ->> 4, ''), '[^1-7]', '', 'g') <> ''
   group by s.scan_id, s.world_id, s.airline_id, f ->> 2;
  get diagnostics n = row_count;
  return n;
end
$function$;

-- The world scanner's results (scripts/scanner/gscan.py), with the same kinds, payloads and answers as before:
-- start (a scan of the default world), airline, airport, finish (which builds the airport summaries); and markets, the
-- weekly report's market summaries for a scan (scripts/report/analyze.py, which owns the market definitions), which
-- replace that scan's earlier ones. Every airline a scan sees becomes an airlines row (change log actor script unless the
-- caller named itself).
create or replace function public.ingest_snapshot(p_secret text, p_kind text, p_payload jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_world bigint; v_scan bigint; v_al bigint; v_res jsonb; n int := 0;
  v_actor text := current_setting('equinox.actor', true); v_detail text := current_setting('equinox.actor_detail', true);
begin
  if not exists (select 1 from public.ingest_secret s where s.secret = p_secret) then raise exception 'not allowed'; end if;
  if p_kind is null or p_kind not in ('start', 'airline', 'airport', 'finish', 'markets') then raise exception 'unknown kind'; end if;
  perform set_config('equinox.actor', coalesce(nullif(v_actor, ''), 'script'), true),
          set_config('equinox.actor_detail', coalesce(nullif(v_detail, ''), 'ingest_snapshot'), true);
  if p_kind = 'start' then
    select x.id into v_world from public.worlds x where x.is_default;
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
      insert into public.game_scan_airlines as x (scan_id, world_id, enterprise_id, airline_id, name, n_flights, n_weekly, n_airports)
      values (v_scan, v_world, (p_payload ->> 'enterprise_id')::int, v_al, p_payload ->> 'name',
              (p_payload ->> 'n_flights')::int, (p_payload ->> 'n_weekly')::int, (p_payload ->> 'n_airports')::int)
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
      insert into public.game_scan_airports as x (scan_id, world_id, airport_code, game_airport_id, info, stations, news)
      values (v_scan, v_world, p_payload ->> 'code', (p_payload ->> 'airport_id')::int, p_payload -> 'info',
              p_payload -> 'stations', p_payload -> 'news')
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
  perform set_config('equinox.actor', coalesce(v_actor, ''), true), set_config('equinox.actor_detail', coalesce(v_detail, ''), true);
  return v_res;
end
$function$;

-- The weekly report's and gander monthly's reads, with the same answers as before: the scans, a scan's airlines (by
-- game ID, the order the scanner reads them in, each with its schedule: null once the schedule is archived) and its
-- airports (in the order the scan stored them); the planner's two documents as pull request 8 left them.
create or replace function public.export_for_report(p_secret text, p_kind text, p_arg text default null)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
begin
  if not exists (select 1 from public.ingest_secret s where s.secret = p_secret) then raise exception 'not allowed'; end if;
  if p_kind = 'snapshots' then
    return (select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'taken_at', s.taken_at, 'week', s.week, 'status', s.status) order by s.id), '[]'::jsonb)
              from public.game_scans s);
  elsif p_kind = 'airlines' then
    return (select coalesce(jsonb_agg(jsonb_build_object('id', a.enterprise_id, 'name', a.name, 'flights', sc.flights, 'n_weekly', a.n_weekly)
                                      order by a.enterprise_id), '[]'::jsonb)
              from public.game_scan_airlines a
              left join public.game_scan_schedules sc on sc.scan_id = a.scan_id and sc.airline_id = a.airline_id
             where a.scan_id = p_arg::bigint);
  elsif p_kind = 'airports' then
    return (select coalesce(jsonb_agg(jsonb_build_object('code', a.airport_code, 'info', a.info, 'stations', a.stations, 'news', a.news)), '[]'::jsonb)
              from public.game_scan_airports a where a.scan_id = p_arg::bigint);
  elsif p_kind = 'planner' then
    -- today's two documents, built from the tables by the adapter's getters (design §8)
    return jsonb_build_object('state', (public.planner_state_get() ->> 'json')::jsonb,
                              'loads', (select coalesce(jsonb_object_agg(g.month, g.json::jsonb), '{}'::jsonb) from public.planner_loads_get() g));
  end if;
  raise exception 'unknown kind';
end
$function$;

-- ============================================================ 6. the backfill (§9 step 4)
-- airline_days from 29 Sep to the last capture day that has ended (and today's, if its capture is already complete):
-- the fleet from delivery dates, the schedule from each rotation's launch date, cash as stored by the old planner
-- (cash_entries) until the capture began, then game_balance; marked source backfill. Then route_days and the days' flows
-- for every UTC day with a flight from 6 Oct, and the airport summaries of every scan already stored.
do $backfill$
declare w bigint := (select x.id from public.worlds x where x.is_default); d date; v_last date; v_flows_to date;
  t0 timestamptz := clock_timestamp(); v_days int := 0; v_flow jsonb; v_scans int := 0; v_rows int := 0; s record;
begin
  v_last := private.capture_day(w, now()) - 1;
  if private.capture_day_complete(w, v_last + 1) then v_last := v_last + 1; end if;
  for d in select g::date from generate_series(date '2026-09-29', v_last, interval '1 day') g loop
    perform private.take_snapshot(w, d, least(private.capture_day_start(w, d + 1), now()), 'backfill', false);
    v_days := v_days + 1;
  end loop;
  select max(coalesce((f.dep_at at time zone 'UTC')::date, f.game_date)) into v_flows_to from public.game_flights f where f.world_id = w;
  v_flow := private.history_flows(w, date '2026-10-06', greatest(coalesce(v_flows_to, date '2026-10-06'), date '2026-10-06'));
  for s in select x.id from public.game_scans x where x.world_id = w order by x.id loop
    v_rows := v_rows + private.scan_summarise(s.id);
    v_scans := v_scans + 1;
  end loop;
  insert into public.job_runs (job, world_id, started_at, finished_at, status, for_day, note, details)
  values ('snapshot', w, t0, clock_timestamp(), 'ok', v_last,
          format('backfill (20261011120000_history): %s day(s) from 29 Sep, route days from 6 Oct', v_days),
          jsonb_build_object('source', 'backfill', 'from', date '2026-09-29', 'to', v_last, 'days', v_days,
                             'airline_days', (select count(*) from public.airline_days x where x.world_id = w),
                             'route_days', v_flow -> 'route_days', 'scans', v_scans, 'scan_airline_airports', v_rows));
  raise notice 'backfill: % airline day(s) for % capture day(s) (29 Sep to %), % route day(s) from 6 Oct to %; airport summaries for % scan(s): % row(s)',
    (select count(*) from public.airline_days x where x.world_id = w), v_days, v_last, v_flow ->> 'route_days',
    coalesce(v_flows_to, date '2026-10-06'), v_scans, v_rows;
end
$backfill$;

-- ============================================================ 7. access (design §5)
-- The new tables: RLS on, one staff read rule each (checked once per query), anon nothing, authenticated read only;
-- only the database's own functions write them. The renamed scan tables keep their staff read rule, rewritten the
-- same way; the write access signed-in accounts still hold on them from Supabase's old defaults (refused by RLS
-- anyway) is revoked in the removal file.
do $access$
declare t text;
begin
  foreach t in array array['airline_days', 'route_days', 'game_scan_schedules', 'scan_airline_airports', 'scan_airline_markets'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('create policy "staff read" on public.%I for select to authenticated using ((select public.is_planner_user()))', t);
    execute format('revoke all on table public.%I from public, anon, authenticated', t);
    execute format('grant select on table public.%I to authenticated', t);
  end loop;
end
$access$;
alter policy "planner staff read snapshots" on public.game_scans rename to "staff read";
alter policy "planner staff read snapshot airlines" on public.game_scan_airlines rename to "staff read";
alter policy "planner staff read snapshot airports" on public.game_scan_airports rename to "staff read";
alter policy "staff read" on public.game_scans using ((select public.is_planner_user()));
alter policy "staff read" on public.game_scan_airlines using ((select public.is_planner_user()));
alter policy "staff read" on public.game_scan_airports using ((select public.is_planner_user()));
revoke all on table public.game_scans, public.game_scan_airlines, public.game_scan_airports from anon;
grant select on table public.game_scans, public.game_scan_airlines, public.game_scan_airports to authenticated;

revoke all on function private.history_fleet(bigint, timestamptz), private.history_schedule(bigint, date),
  private.history_cash(bigint, date, timestamptz), private.history_flows(bigint, date, date),
  private.take_snapshot(bigint, date, timestamptz, text, boolean), private.snapshot_due(bigint, date, timestamptz),
  private.scan_airline(bigint, int, text), private.scan_summarise(bigint)
  from public, anon, authenticated;
-- the scripts call these with the ingest secret, signed out, as before
revoke all on function public.ingest_snapshot(text, text, jsonb), public.export_for_report(text, text, text) from public, anon, authenticated;
grant execute on function public.ingest_snapshot(text, text, jsonb), public.export_for_report(text, text, text) to anon, authenticated;

-- ============================================================ 8. descriptions (decision #10)
comment on table public.airline_days is 'The daily history (decision #15, design §3.10, §7): one row per airline of our groups per capture day (design §2: the evening it was taken, 10:00 to 10:00 UTC), kept for good. Point-in-time figures (fleet, schedule, cash) are fixed when the snapshot is taken (private.take_snapshot, by the capture when a world''s capture for the day is complete) and replaced by a later complete capture of the same day; the flows are for the UTC day of the same date and recomputed for the two days after, as late captures fill them in. Filled back from 29 Sep (source backfill). Not in the change log. Staff read it; only the database writes it.';
comment on column public.airline_days.day is 'The capture day (design §2); the flows are for the UTC day of this date';
comment on column public.airline_days.complete is 'True when that day''s capture was complete for the whole world (every active airline of our groups, all five pages)';
comment on column public.airline_days.source is 'capture (taken when the day''s capture was complete), fallback (the 10:00 UTC job, #13 pull request 7) or backfill (filled back by 20261011120000_history)';
comment on column public.airline_days.taken_at is 'The moment the point-in-time figures stand for: when the capture''s last page arrived, the job''s time, or for a backfilled day the end of that capture day';
comment on column public.airline_days.aircraft_by_type is 'Aircraft flying, by type: {"A321 NEO LIGHT": 50, ...}. Flying from arrival in the game (delivery) until retired; backfilled days from delivery dates (an aircraft with no delivery record from the start)';
comment on column public.airline_days.aircraft_total is 'Aircraft flying (the sum of aircraft_by_type)';
comment on column public.airline_days.on_order is 'Aircraft ordered and not yet arrived';
comment on column public.airline_days.weekly_departures is 'Departures a week in the schedule (flight_legs, each leg''s weekdays), counting rotations launched by that day (backfilled days assume nothing was dropped)';
comment on column public.airline_days.weekly_seats is 'Seats a week in the schedule: each leg''s departures times its aircraft''s seats (its cabin, or its type''s maximum)';
comment on column public.airline_days.destinations is 'Distinct destinations in the schedule (the far end of each route flown)';
comment on column public.airline_days.cash is 'Cash, AS$: the day''s latest balance of account 2800 (game_balance), or with no capture the figure typed or kept from before the capture (cash_entries)';
comment on column public.airline_days.fixed_next7 is 'Payments the events page lists for the 7 days after that balance, AS$ (as capture_cash works them out); typed figures from cash_entries';
comment on column public.airline_days.cash_at is 'The balance''s capture time; null when the cash was typed or kept from before the capture';
comment on column public.airline_days.flights_flown is 'Flights that departed that UTC day (game_flights rows with loads or with passenger income)';
comment on column public.airline_days.passengers is 'Passengers on those flights: from the loads page, or the statement''s count where the loads weren''t captured';
comment on column public.airline_days.seats_flown is 'Seats on the flights whose loads were captured';
comment on column public.airline_days.load_pct is 'Passengers ÷ seats on the flights whose loads were captured, percent';
comment on column public.airline_days.eco_load_pct is 'Economy passengers ÷ economy seats, percent';
comment on column public.airline_days.revenue is 'Income of every statement block that day, AS$';
comment on column public.airline_days.flight_costs is 'Costs of every statement block that day, AS$ (fuel, fees, handling, maintenance ...)';
comment on column public.airline_days.flight_profit is 'revenue − flight_costs, before leases, salaries and purchases, AS$';
comment on column public.airline_days.leases_paid is 'Lease payments posted that UTC day (game_payments kind lease), AS$';
comment on column public.airline_days.salaries_paid is 'Salaries posted that UTC day (kind salaries: the week-end closing), AS$';
comment on column public.airline_days.purchases_paid is 'Aircraft, deposits, cabins and refits paid that UTC day (kinds purchase, deposit, cabin, refit), AS$';

comment on table public.route_days is 'The daily history per route, direction and UTC day (design §3.10, §7): each airline''s flights, passengers, seats, money and average economy fare, from game_flights (a flight''s day is the UTC date it departs), kept for good after game_flights is archived. Recomputed for the snapshot''s day and the two before; filled back from 6 Oct. Not in the change log. Staff read it; only the database writes it.';
comment on column public.route_days.route_id is 'The route, when the flights were matched to one; set to null if the planner removes the route later (the airports keep the history)';
comment on column public.route_days.day is 'The UTC date the flights departed';
comment on column public.route_days.flights is 'Flights (game_flights rows with loads or passenger income)';
comment on column public.route_days.passengers is 'From the loads page, or the statement''s count where the loads weren''t captured';
comment on column public.route_days.seats is 'Seats on the flights whose loads were captured; null when none were';
comment on column public.route_days.revenue is 'AS$, from the statement (costs and profit likewise; profit = revenue − costs)';
comment on column public.route_days.eco_fare_avg is 'Average economy fare, AS$, weighted by economy passengers';

comment on table public.game_scans is 'One row per world scan (design §3.9; was game_snapshots): when it ran, the week, its status and a note, with its world. Kept for good. Written by ingest_snapshot(), from scripts/scanner/gscan.py. Read by export_for_report() for the weekly report and gander monthly.';
comment on column public.game_scans.world_id is 'The world scanned';
comment on table public.game_scan_airlines is 'Each airline''s totals in a world scan (design §3.9; was game_snapshot_airlines): flights, weekly departures and airports, with its airlines row. Kept for good; the full schedule is in game_scan_schedules. Written by ingest_snapshot(). Read by export_for_report().';
comment on column public.game_scan_airlines.scan_id is 'The scan (game_scans)';
comment on column public.game_scan_airlines.enterprise_id is 'The airline''s game ID as the scan read it (airlines.game_id)';
comment on column public.game_scan_airlines.name is 'The airline''s name as the scan read it';
comment on column public.game_scan_airlines.flights is 'Retired (#13 pull request 6): the schedule moved to game_scan_schedules; this copy is dropped by 20261011120100_history_removals.sql';
comment on column public.game_scan_airlines.n_flights is 'Flights in its schedule';
comment on column public.game_scan_airlines.n_weekly is 'Departures a week';
comment on column public.game_scan_airlines.n_airports is 'Airports it serves';
comment on column public.game_scan_airlines.airline_id is 'The airline (airlines, by game ID): every airline a scan sees has a row';
comment on table public.game_scan_schedules is 'Each airline''s full schedule in a world scan (design §3.9): one JSON list per airline, each flight as [code, number, from, to, weekdays, departure, arrival, aircraft type, operator]. Kept one month, then archived (#13 pull request 7). Written by ingest_snapshot(). Read by export_for_report() and the airport summaries (private.scan_summarise).';
comment on table public.game_scan_airports is 'Each scanned airport''s page in a world scan (design §3.9; was game_snapshot_airports): its details, the airlines stationed there and its news. Kept one month, then archived (#13 pull request 7). Written by ingest_snapshot(). Read by export_for_report().';
comment on column public.game_scan_airports.airport_code is 'IATA code';
comment on column public.game_scan_airports.game_airport_id is 'The game''s ID for the airport';
comment on column public.game_scan_airports.stations is 'The airlines stationed there with their departures a week: [{enterprise_id, name, weekly, alliance, interline}]';
comment on table public.scan_airline_airports is 'Summary of each world scan, kept for good (design §3.9, §11 choice 2): per airline and airport, its departures a week from there and how many destinations it flies to from there. Built from the scan''s schedules when it finishes (private.scan_summarise); filled for every scan stored before 11 Oct.';
comment on column public.scan_airline_airports.weekly_departures is 'Departures a week from the airport';
comment on column public.scan_airline_airports.destinations is 'Distinct airports it flies to from there';
comment on table public.scan_airline_markets is 'Summary of each world scan, kept for good (design §3.9, §11 choice 2): per airline and market (the weekly report''s market names, e.g. Transatlantic, Intra-Europe), its passenger departures a week and city pairs. Sent by the weekly report''s script (scripts/report/analyze.py, which owns the market definitions) through ingest_snapshot() kind markets, replacing that scan''s earlier ones; scripts/report/scan_markets.py fills past scans.';
comment on column public.scan_airline_markets.market is 'The weekly report''s market name';
comment on column public.scan_airline_markets.weekly_departures is 'Passenger departures a week in the market (freighters left out, as the report counts them)';
comment on column public.scan_airline_markets.city_pairs is 'Distinct city pairs (either direction) it flies in the market';

comment on function private.capture_page(bigint) is 'Parses one stored capture page into the capture tables, using the page''s own capture time throughout: statement lines into game_statement, folded into game_flights and game_payments; events into game_events (with due_at where known); loads into game_flights; the income statement and balance sheet into game_pnl and game_balance (with capture_day), each row''s figures and capture time from the same capture, the latest (#13 pull request 6). Then money and loads are matched.';
comment on function private.capture_store(bigint, text, text, text, jsonb, timestamp with time zone, boolean) is 'Stores one page for an airline of the given world and parses it, at the given capture time, and says whether that capture day is now complete. When the page completes the world''s capture for the day (private.snapshot_due), takes the daily snapshot (private.take_snapshot, one job_runs row, ok or failed; a failure never loses the page) and answers with it under snapshot. Refuses a page for an airline outside the world. capture_ingest() calls it with now(); the tests replay saved pages with their own times.';
comment on function private.history_fleet(bigint, timestamp with time zone) is 'The daily history''s fleet at a moment, per active airline of our groups (design §7, §9 step 4): aircraft flying (by type, and the total) from arrival in the game (delivery_at; one with no delivery record from the start) until retired, unless still marked on order; on order from the order date until then. With the moment now it agrees with aircraft.status.';
comment on function private.history_schedule(bigint, date) is 'The daily history''s schedule as it stood on a day, per airline: departures and seats a week and destinations, from the flight legs of every rotation launched by that day (one with no launch date from the start), assuming nothing was dropped.';
comment on function private.history_cash(bigint, date, timestamp with time zone) is 'The daily history''s cash for a capture day, per active airline of our groups (design §7): the day''s latest balance of account 2800 up to the moment, with the payments due in the 7 days after it (as capture_cash); with no balance that day, cash_entries by the planner''s date.';
comment on function private.history_flows(bigint, date, date) is 'The daily history''s flows for a span of UTC days (design §7): route_days replaced for those days, and each airline_days row of those days given its flights, passengers, seats, loads, money and payments, from game_flights and game_payments. Returns how many rows of each it wrote.';
comment on function private.take_snapshot(bigint, date, timestamp with time zone, text, boolean) is 'The daily snapshot of a world''s capture day (design §7): point-in-time figures (fleet, schedule, cash) as at p_at (default now) into airline_days for each active airline of our groups, with source (capture, fallback or backfill) and whether the day''s capture was complete; then (p_flows) the flows of that UTC day and the two before. A later snapshot replaces the point-in-time figures, but a fallback or backfill never replaces one from a complete capture. Called by the capture when a day completes; pull request 7''s 10:00 UTC fallback calls it too.';
comment on function private.snapshot_due(bigint, date, timestamp with time zone) is 'Whether a page at p_at completes a world''s capture for the day: every active airline of our groups has all five pages since the day started, or since the last snapshot taken from a complete capture that day. So one snapshot per complete capture, taken by its last page.';
comment on function private.scan_airline(bigint, integer, text) is 'The airlines row of an airline a world scan saw, by game ID, added when new (design §3.9: rivals can then be placed in groups); a rival''s game_name follows the game, ours are left alone. Null without a game ID.';
comment on function private.scan_summarise(bigint) is 'Builds a world scan''s airport summaries (scan_airline_airports) from its schedules: per airline and airport, departures a week and destinations. Run when a scan finishes; a scan whose schedules were archived keeps what it has. Returns the rows written.';
comment on function public.capture_ingest(text, text, text, text, jsonb) is 'Entry point for the in-game capture. Checks the capture key, which belongs to one world; finds the airline by the game''s ID or, from older userscripts, by name, and refuses one outside the key''s world; keeps the raw page 14 days and parses it (private.capture_store, private.capture_page): bank statement into game_flights and game_payments, loads into game_flights. Answers with the capture day and whether it is complete; the page that completes the world''s capture for the day also takes the daily snapshot (airline_days, route_days) and answers with it.';
comment on function public.ingest_snapshot(text, text, jsonb) is 'Receives the world scanner''s results (start, airlines, airports, finish) into game_scans, game_scan_airlines, game_scan_schedules and game_scan_airports; finish builds the scan''s airport summaries. Kind markets takes the weekly report''s market summaries for a scan (scan_airline_markets). Every airline a scan sees gets an airlines row (change log actor script). Same kinds, payloads and answers as before #13. Needs the ingest secret.';
comment on function public.export_for_report(text, text, text) is 'Exports for the weekly report and gander monthly: the world scans (snapshots), a scan''s airlines (with their schedules) and airports, from game_scans and its tables with the same answers as before #13, and the planner ({state, loads}: today''s planner_state and planner_loads documents, built from the tables by planner_state_get() and planner_loads_get()). Needs the ingest secret.';
comment on column public.game_balance.captured_at is 'When the capture that gave the figures was taken (the latest capture that UTC date, since #13 pull request 6)';
comment on column public.game_pnl.captured_at is 'When the capture that gave the figures was taken (the latest capture that UTC date, since #13 pull request 6)';
comment on column public.game_balance.capture_day is 'The capture day (design §2): the evening of the capture that gave the figures';
comment on column public.game_pnl.capture_day is 'The capture day (design §2): the evening of the capture that gave the figures';
comment on table public.game_balance is 'The balance-sheet page from the nightly capture: one row per airline, account and UTC date, each with the figures and capture time of that date''s latest capture. Account 2800 is cash. Written by the capture (private.capture_page). Read by the planner (Review: the group today, Cash next 14 days), capture_cash, the daily history and export_capture().';
comment on table public.game_pnl is 'The game''s income statement per airline and UTC date, for the current, last and total periods, with the figures and capture time of that date''s latest capture. Written by the capture (private.capture_page). Not read by any screen yet; kept for reports.';

select set_config('equinox.change_log', '', true), set_config('equinox.actor', '', true),
       set_config('equinox.actor_detail', '', true);

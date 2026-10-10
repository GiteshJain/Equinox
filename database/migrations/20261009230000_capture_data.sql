-- The capture data in the new model (decision #13, build pull request 3).
-- Design: docs/design/2026-10-09-data-model.md (§2, §3.8, §3.12, §3.13, §5, §9 step 2). Spec:
-- docs/specs/2026-10-09-capture-data.md.
--
-- Adds and changes; removes nothing (the removals are in 20261009230100_capture_data_removals.sql, which Gitesh runs):
--   1. helpers in private: the capture day, airport offsets, the statement's line types, finding an airline;
--   2. world_id and airline_id on every capture table (plus game_statement.flight_id, game_events.due_at, and
--      capture_day on game_balance and game_pnl), filled for every existing row; world_id on capture_keys;
--   3. game_flights (one row per flown flight: loads and money) and game_payments (statement lines not tied to a flight),
--      with RLS: staff read, nobody else, and only the capture's functions write;
--   4. the capture itself, rewritten in private: parsing a page, folding statement blocks into game_flights and the
--      other lines into game_payments, matching money to loads, completeness by world, and planner_loads as today;
--      capture_ingest() keeps its name and arguments, and capture_airlines() is new;
--   5. the backfill: game_flights from every loads row and every statement line since 6 Oct, game_payments from the
--      other lines (logged as migration, the change log off);
--   6. game_loads becomes a view: the table is renamed game_loads_before_13 and kept (§3.13); game_loads,
--      game_flight_pnl and game_ops_recent are views over game_flights that return today's columns and rows;
--   7. export_capture() leaves the new columns out, so it returns exactly what it did;
--   8. descriptions.
-- Run it after an evening's capture has finished, so no capture runs half-way through it.

select set_config('equinox.actor', 'migration', true),
       set_config('equinox.actor_detail', '20261009230000_capture_data', true),
       set_config('equinox.change_log', 'off', true);

-- ============================================================ 1. helpers
-- When a world's capture day starts, in UTC (design §2): the setting capture_day_starts_utc, 10:00 until it is set
create or replace function private.capture_day_start(p_world_id bigint, p_day date)
 returns timestamptz
 language sql
 stable
 set search_path to ''
as $function$
  select (p_day + coalesce((select (s.value #>> '{}')::time from public.settings s
                             where s.world_id = p_world_id and s.airline_id is null and s.key = 'capture_day_starts_utc'),
                           time '10:00')) at time zone 'UTC'
$function$;

-- The capture day a moment belongs to: the UTC date of (the moment − the start), so one evening is one day
create or replace function private.capture_day(p_world_id bigint, p_at timestamptz)
 returns date
 language sql
 stable
 set search_path to ''
as $function$
  select ((p_at at time zone 'UTC')
          - coalesce((select (s.value #>> '{}')::time from public.settings s
                       where s.world_id = p_world_id and s.airline_id is null and s.key = 'capture_day_starts_utc'),
                     time '10:00')::interval)::date
$function$;

-- An airport's UTC offset in a world, in minutes (design §3.2); null while it isn't known (airports fill in with #13's
-- pull request 4)
create or replace function private.airport_offset_min(p_world_id bigint, p_code text)
 returns int
 language sql
 stable
 set search_path to ''
as $function$
  select round(coalesce(wa.utc_offset_override, a.utc_offset) * 60)::int
    from public.airports a
    left join public.world_airports wa on wa.world_id = p_world_id and wa.airport_code = a.code
   where a.code = p_code
$function$;

-- A local date and clock time ("07:30") at a fixed offset, as a moment; null if any part is missing
create or replace function private.local_to_utc(p_date date, p_time text, p_offset_min int)
 returns timestamptz
 language sql
 immutable
 set search_path to ''
as $function$
  select case when p_date is not null and p_offset_min is not null and p_time ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
              then ((p_date + p_time::time) - make_interval(mins => p_offset_min)) at time zone 'UTC' end
$function$;

-- A loads row's scheduled times (design §3.8, §4): departure from the origin's offset; arrival = departure + block,
-- where block = arrival local − departure local − (destination offset − origin offset), wrapped into 0 to 24 hours
create or replace function private.loads_times(p_world_id bigint, p_game_date date, p_dep_local text, p_arr_local text,
                                               p_origin text, p_dest text, out dep_at timestamptz, out arr_at timestamptz)
 language plpgsql
 stable
 set search_path to ''
as $function$
declare o int; d int;
begin
  o := private.airport_offset_min(p_world_id, p_origin);
  dep_at := private.local_to_utc(p_game_date, p_dep_local, o);
  if dep_at is null or coalesce(p_arr_local, '') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then return; end if;
  d := private.airport_offset_min(p_world_id, p_dest);
  if d is null then return; end if;
  arr_at := dep_at + make_interval(mins => (((split_part(p_arr_local, ':', 1)::int * 60 + split_part(p_arr_local, ':', 2)::int)
                                             - (split_part(p_dep_local, ':', 1)::int * 60 + split_part(p_dep_local, ':', 2)::int)
                                             - (d - o)) % 1440 + 1440) % 1440);
end
$function$;

-- The statement's line types, as game_flight_pnl has always counted them
create or replace function private.statement_category(p_descr text)
 returns text
 language sql
 immutable
 set search_path to ''
as $function$
  select case
    when p_descr = 'Passenger transport income' then 'pax_income'
    when p_descr = 'Cargo transport income' then 'cargo_income'
    when p_descr like 'Fuel%' then 'fuel'
    when p_descr like 'On-board services%' then 'onboard'
    when p_descr like 'Aircraft handling%' or p_descr like 'Passenger handling%' or p_descr like 'Cargo logistic%' then 'handling'
    when p_descr like 'Airport landing fee%' then 'landing'
    when p_descr like 'Air traffic control fee%' then 'atc'
    when p_descr like 'Maintenance of%' then 'maintenance'
    else 'other' end
$function$;

-- The kind of a payment that isn't tied to a flight (game_payments.kind); other for anything else
create or replace function private.payment_kind(p_descr text)
 returns text
 language sql
 immutable
 set search_path to ''
as $function$
  select case
    when p_descr ilike 'Leasing rate%' then 'lease'
    when p_descr ilike 'Week-end closing%' or p_descr ilike '%salaries%' then 'salaries'
    when p_descr ilike '%deposit%' then 'deposit'
    when p_descr ilike '%purchase%' then 'purchase'
    when p_descr ilike '%configuration%' then 'refit'
    when p_descr ilike '%cabin%' then 'cabin'
    else 'other' end
$function$;

-- A line that never belongs to a flight: a lease, salaries, a deposit, a purchase, a refit or a cabin, or a line the
-- parser put outside every flight (block 0). Everything else is grouped into flights by minute and block.
create or replace function private.is_payment_line(p_descr text, p_blk int)
 returns boolean
 language sql
 immutable
 set search_path to ''
as $function$
  select coalesce(p_blk, 1) = 0 or private.payment_kind(p_descr) <> 'other'
$function$;

-- The aircraft a payment names, e.g. "Leasing rate for B-0161"
create or replace function private.payment_registration(p_descr text)
 returns text
 language sql
 immutable
 set search_path to ''
as $function$
  select substring(p_descr from '(?:for|of) ([A-Z0-9]{1,3}-[A-Z0-9]{2,6}|N[0-9]{1,5}[A-Z]{0,2})(?:$|[ ,.;(])')
$function$;

-- The airline a page is for, among the airlines of our groups in the key's world: by the game's ID (what the userscript
-- sends from version 1.3), or by name as today's userscript and bookmark send it. Null when none or more than one fits.
create or replace function private.capture_find_airline(p_world_id bigint, p_airline text)
 returns bigint
 language sql
 stable
 set search_path to ''
as $function$
  select case when count(*) = 1 then min(a.id) end
    from public.airlines a
    join public.groups g on g.id = a.group_id and g.world_id = a.world_id
   where a.world_id = p_world_id and g.kind = 'ours' and p_airline is not null
     and case
           when btrim(p_airline) ~ '^[0-9]{1,9}$' then a.game_id = btrim(p_airline)::int
           else lower(btrim(p_airline)) in (lower(a.planner_name), lower(a.public_name), lower(a.game_name))
                -- the names the capture has matched since 7 Oct, by their start (e.g. "Pan Am" for Pan American)
                or exists (select 1 from (values ('pan am%', 'Pan American'), ('kingfisher%', 'Kingfisher'),
                                                 ('ryanair%', 'Ryanair'), ('virgin%', 'Virgin Atlantic'),
                                                 ('china eastern%', 'China Eastern'), ('malaysia%', 'Malaysia Airlines'))
                                         as legacy (pattern, planner_name)
                            where p_airline ilike legacy.pattern and legacy.planner_name = a.planner_name)
         end
$function$;

-- ============================================================ 2. ids on the capture tables (§3.8)
-- Every capture row so far is Gander's and names one of our airlines by the planner's name, as capture_ingest() has
-- always written it. A row that doesn't stops the migration and says which names it found.
do $check$
declare t text; bad text;
begin
  foreach t in array array['game_capture_raw', 'game_statement', 'game_events', 'game_balance', 'game_pnl', 'game_loads'] loop
    execute format('select string_agg(distinct x.airline, '', '') from public.%I x
                     where not exists (select 1 from public.airlines a join public.worlds w on w.id = a.world_id and w.is_default
                                        where a.planner_name = x.airline)', t) into bad;
    if bad is not null then
      raise exception 'capture data: % names airlines that aren''t ours in the default world: %', t, bad;
    end if;
  end loop;
end
$check$;

alter table public.capture_keys add column world_id bigint;
alter table public.game_capture_raw add column world_id bigint, add column airline_id bigint;
alter table public.game_statement add column world_id bigint, add column airline_id bigint, add column flight_id bigint;
alter table public.game_events add column world_id bigint, add column airline_id bigint, add column due_at timestamptz;
alter table public.game_balance add column world_id bigint, add column airline_id bigint, add column capture_day date;
alter table public.game_pnl add column world_id bigint, add column airline_id bigint, add column capture_day date;

update public.capture_keys set world_id = (select w.id from public.worlds w where w.is_default);
update public.game_capture_raw x set world_id = a.world_id, airline_id = a.id
  from public.airlines a join public.worlds w on w.id = a.world_id and w.is_default where a.planner_name = x.airline;
update public.game_statement x set world_id = a.world_id, airline_id = a.id
  from public.airlines a join public.worlds w on w.id = a.world_id and w.is_default where a.planner_name = x.airline;
update public.game_events x set world_id = a.world_id, airline_id = a.id,
       due_at = private.local_to_utc(x.event_date, x.event_time, private.airport_offset_min(a.world_id, a.home_airport_code))
  from public.airlines a join public.worlds w on w.id = a.world_id and w.is_default where a.planner_name = x.airline;
update public.game_balance x set world_id = a.world_id, airline_id = a.id
  from public.airlines a join public.worlds w on w.id = a.world_id and w.is_default where a.planner_name = x.airline;
update public.game_pnl x set world_id = a.world_id, airline_id = a.id
  from public.airlines a join public.worlds w on w.id = a.world_id and w.is_default where a.planner_name = x.airline;
-- capture_day: the evening of the latest page that wrote the row (a later page the same UTC date overwrites the
-- figures), or of the row's own capture time once that page is no longer kept
update public.game_balance x set capture_day = coalesce(
    (select private.capture_day(x.world_id, max(r.captured_at)) from public.game_capture_raw r
      where r.airline_id = x.airline_id and r.kind = 'balance' and (r.captured_at at time zone 'UTC')::date = x.captured_on),
    private.capture_day(x.world_id, x.captured_at));
update public.game_pnl x set capture_day = coalesce(
    (select private.capture_day(x.world_id, max(r.captured_at)) from public.game_capture_raw r
      where r.airline_id = x.airline_id and r.kind = 'pnl' and (r.captured_at at time zone 'UTC')::date = x.captured_on),
    private.capture_day(x.world_id, x.captured_at));

alter table public.capture_keys alter column world_id set not null,
  add constraint capture_keys_world_fkey foreign key (world_id) references public.worlds (id);
create index capture_keys_world_id_idx on public.capture_keys (world_id);
alter table public.game_capture_raw alter column world_id set not null, alter column airline_id set not null,
  add constraint game_capture_raw_world_fkey foreign key (world_id) references public.worlds (id),
  add constraint game_capture_raw_airline_fkey foreign key (airline_id, world_id) references public.airlines (id, world_id);
create index game_capture_raw_airline_captured_idx on public.game_capture_raw (airline_id, captured_at);
create index game_capture_raw_world_captured_idx on public.game_capture_raw (world_id, captured_at);
alter table public.game_statement alter column world_id set not null, alter column airline_id set not null,
  add constraint game_statement_world_fkey foreign key (world_id) references public.worlds (id),
  add constraint game_statement_airline_fkey foreign key (airline_id, world_id) references public.airlines (id, world_id);
create index game_statement_airline_ts_idx on public.game_statement (airline_id, ts);
create index game_statement_world_ts_idx on public.game_statement (world_id, ts);
alter table public.game_events alter column world_id set not null, alter column airline_id set not null,
  add constraint game_events_world_fkey foreign key (world_id) references public.worlds (id),
  add constraint game_events_airline_fkey foreign key (airline_id, world_id) references public.airlines (id, world_id);
create index game_events_airline_event_date_idx on public.game_events (airline_id, event_date);
create index game_events_world_event_date_idx on public.game_events (world_id, event_date);
alter table public.game_balance alter column world_id set not null, alter column airline_id set not null,
  alter column capture_day set not null,
  add constraint game_balance_world_fkey foreign key (world_id) references public.worlds (id),
  add constraint game_balance_airline_fkey foreign key (airline_id, world_id) references public.airlines (id, world_id);
create index game_balance_airline_captured_idx on public.game_balance (airline_id, captured_at);
create index game_balance_world_captured_idx on public.game_balance (world_id, captured_at);
alter table public.game_pnl alter column world_id set not null, alter column airline_id set not null,
  alter column capture_day set not null,
  add constraint game_pnl_world_fkey foreign key (world_id) references public.worlds (id),
  add constraint game_pnl_airline_fkey foreign key (airline_id, world_id) references public.airlines (id, world_id);
create index game_pnl_airline_captured_idx on public.game_pnl (airline_id, captured_at);
create index game_pnl_world_captured_idx on public.game_pnl (world_id, captured_at);

-- ============================================================ 3. game_flights and game_payments (§3.8)
create table public.game_flights (
  id bigint generated always as identity primary key,
  world_id bigint not null references public.worlds (id),
  airline_id bigint not null,
  game_date date,
  flight_no int,
  origin_code text,
  dest_code text,
  dep_local text,
  arr_local text,
  dep_at timestamptz,
  arr_at timestamptz,
  posted_at timestamptz,
  statement_blk smallint,
  statement_routes smallint,
  route_id bigint,
  aircraft_id bigint,
  registration text,
  maint_registration text,
  status text,
  eco_pax int,
  eco_seats int,
  eco_fare numeric(14,2),
  eco_pct smallint,
  bus_pax int,
  bus_seats int,
  bus_fare numeric(14,2),
  bus_pct smallint,
  fst_pax int,
  fst_seats int,
  fst_fare numeric(14,2),
  fst_pct smallint,
  cargo_units int,
  cargo_cap int,
  cargo_rate numeric(14,2),
  cargo_pct smallint,
  pax_income numeric(14,2),
  cargo_income numeric(14,2),
  fuel numeric(14,2),
  onboard numeric(14,2),
  handling numeric(14,2),
  landing numeric(14,2),
  atc numeric(14,2),
  maintenance numeric(14,2),
  income_total numeric(14,2),
  cost_total numeric(14,2),
  profit numeric(14,2) generated always as (income_total - cost_total) stored,
  statement_pax int,
  loads_captured_at timestamptz,
  money_captured_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint game_flights_id_airline_key unique (id, airline_id),
  constraint game_flights_airline_fkey foreign key (airline_id, world_id) references public.airlines (id, world_id),
  constraint game_flights_route_fkey foreign key (route_id, world_id) references public.routes (id, world_id),
  constraint game_flights_aircraft_fkey foreign key (aircraft_id, world_id) references public.aircraft (id, world_id),
  -- a row holds a flight's loads, its money, or both
  constraint game_flights_loads_or_money_check check (flight_no is not null or posted_at is not null),
  constraint game_flights_loads_check check (flight_no is null or (game_date is not null and dep_local is not null)),
  constraint game_flights_money_check
    check (posted_at is null or (statement_blk is not null and income_total is not null and cost_total is not null))
);
-- the loads page's own key (today's game_loads key), which works before the airports' offsets are known
create unique index game_flights_loads_key on public.game_flights (airline_id, game_date, flight_no, dep_local)
  where flight_no is not null;
create unique index game_flights_dep_key on public.game_flights (airline_id, dep_at, flight_no) where flight_no is not null;
create unique index game_flights_money_key on public.game_flights (airline_id, posted_at, statement_blk)
  where posted_at is not null;
create index game_flights_world_dep_idx on public.game_flights (world_id, dep_at);
create index game_flights_airline_game_date_idx on public.game_flights (airline_id, game_date);
create index game_flights_route_dep_idx on public.game_flights (route_id, dep_at);
create index game_flights_aircraft_id_idx on public.game_flights (aircraft_id);

create table public.game_payments (
  id bigint generated always as identity primary key,
  world_id bigint not null references public.worlds (id),
  airline_id bigint not null,
  paid_at timestamptz not null,
  kind text not null check (kind in ('lease', 'salaries', 'purchase', 'deposit', 'cabin', 'refit', 'other')),
  registration text,
  aircraft_id bigint,
  descr text not null,
  amount numeric(14,2) not null,
  side text not null check (side in ('D', 'C')),
  occ int not null,
  statement_blk smallint,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- its index also serves (airline_id, paid_at), so that index isn't made twice
  constraint game_payments_line_key unique (airline_id, paid_at, descr, amount, occ),
  constraint game_payments_airline_fkey foreign key (airline_id, world_id) references public.airlines (id, world_id),
  constraint game_payments_aircraft_fkey foreign key (aircraft_id, world_id) references public.aircraft (id, world_id)
);
create index game_payments_world_paid_idx on public.game_payments (world_id, paid_at);
create index game_payments_aircraft_id_idx on public.game_payments (aircraft_id);

alter table public.game_statement
  add constraint game_statement_flight_fkey foreign key (flight_id, airline_id) references public.game_flights (id, airline_id);
create index game_statement_flight_id_idx on public.game_statement (flight_id);

create trigger set_updated_at before insert or update on public.game_flights
  for each row execute function private.set_updated_at();
create trigger set_updated_at before insert or update on public.game_payments
  for each row execute function private.set_updated_at();

-- ============================================================ 4. the capture, in private (§3.8, §5)
-- The world a capture key belongs to; null for a key that doesn't match
create or replace function private.capture_key_world(p_key text)
 returns bigint
 language sql
 stable
 set search_path to ''
as $function$
  select k.world_id from public.capture_keys k
   where p_key is not null and extensions.crypt(p_key, k.key_hash) = k.key_hash
   order by k.id
   limit 1
$function$;

-- A statement's flights: its lines grouped by minute and block number (blk), as game_flight_pnl has always grouped
-- them, leaving out the payments. A block is a flight when any line is a flight's (income, fuel, handling, fees,
-- maintenance) or names a route; otherwise its lines are payments too.
create or replace function private.statement_blocks(p_airline_id bigint, p_minutes timestamptz[])
 returns table (ts timestamptz, blk int, is_flight boolean, route text, routes_n int, pax int, tail text,
                pax_income numeric, cargo_income numeric, fuel numeric, onboard numeric, handling numeric,
                landing numeric, atc numeric, maintenance numeric, income_total numeric, cost_total numeric,
                captured_at timestamptz)
 language sql
 stable
 set search_path to ''
as $function$
  select s.ts, s.blk,
         bool_or(c.cat <> 'other' or c.route is not null),
         max(c.route), count(distinct c.route)::int,
         max((substring(s.descr from 'Passenger handling of (\d+) passengers'))::int),
         max(substring(s.descr from 'Maintenance of ([A-Z0-9-]+)')),
         sum(s.amount) filter (where c.cat = 'pax_income'), sum(s.amount) filter (where c.cat = 'cargo_income'),
         sum(s.amount) filter (where c.cat = 'fuel'), sum(s.amount) filter (where c.cat = 'onboard'),
         sum(s.amount) filter (where c.cat = 'handling'), sum(s.amount) filter (where c.cat = 'landing'),
         sum(s.amount) filter (where c.cat = 'atc'), sum(s.amount) filter (where c.cat = 'maintenance'),
         coalesce(sum(s.amount) filter (where s.side = 'C'), 0),
         coalesce(sum(s.amount) filter (where s.side is distinct from 'C'), 0),
         max(s.captured_at)
    from public.game_statement s
    cross join lateral (select private.statement_category(s.descr) as cat,
                               substring(s.descr from '\(([A-Z]{3}-[A-Z]{3})\)') as route) c
   where s.airline_id = p_airline_id and s.ts = any (p_minutes) and not private.is_payment_line(s.descr, s.blk)
   group by s.ts, s.blk
$function$;

-- Folds the statement lines of the given minutes into game_flights (one row per flight block) and game_payments (the
-- rest), and ties each line to its flight. Run after every statement page for the minutes it holds; the backfill runs
-- it for every minute. Blocks the parser numbered differently since are taken apart and folded again.
create or replace function private.fold_statement(p_airline_id bigint, p_minutes timestamptz[])
 returns int
 language plpgsql
 set search_path to ''
as $function$
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

  -- 5. every other line is a payment, one row per statement line
  insert into public.game_payments as p (world_id, airline_id, paid_at, kind, registration, descr, amount, side, occ,
         statement_blk)
  select v_world, p_airline_id, s.ts, private.payment_kind(s.descr), private.payment_registration(s.descr), s.descr,
         s.amount, s.side, s.occ, s.blk
    from public.game_statement s
   where s.airline_id = p_airline_id and s.ts = any (p_minutes) and s.flight_id is null
  on conflict (airline_id, paid_at, descr, amount, occ) do update set
    kind = excluded.kind, registration = excluded.registration, side = excluded.side, statement_blk = excluded.statement_blk
  where (p.kind, p.registration, p.side, p.statement_blk)
        is distinct from (excluded.kind, excluded.registration, excluded.side, excluded.statement_blk);
  delete from public.game_payments p
   where p.airline_id = p_airline_id and p.paid_at = any (p_minutes)
     and not exists (select 1 from public.game_statement s
                      where s.airline_id = p_airline_id and s.ts = p.paid_at and s.descr = p.descr
                        and s.amount = p.amount and s.occ = p.occ and s.flight_id is null);
  return v_n;
end
$function$;

-- One flight: the loads row's columns move into the money row, and the loads row goes
create or replace function private.merge_flight(p_money_id bigint, p_loads_id bigint)
 returns boolean
 language plpgsql
 set search_path to ''
as $function$
declare l public.game_flights;
begin
  perform 1 from public.game_flights where id = p_money_id and flight_no is null and posted_at is not null for update;
  if not found then return false; end if;
  delete from public.game_flights where id = p_loads_id and posted_at is null and flight_no is not null returning * into l;
  if not found then return false; end if;
  update public.game_flights
     set game_date = l.game_date, flight_no = l.flight_no, origin_code = l.origin_code, dest_code = l.dest_code,
         dep_local = l.dep_local, arr_local = l.arr_local, dep_at = l.dep_at, arr_at = l.arr_at,
         route_id = coalesce(route_id, l.route_id), aircraft_id = coalesce(aircraft_id, l.aircraft_id),
         registration = l.registration, status = l.status,
         eco_pax = l.eco_pax, eco_seats = l.eco_seats, eco_fare = l.eco_fare, eco_pct = l.eco_pct,
         bus_pax = l.bus_pax, bus_seats = l.bus_seats, bus_fare = l.bus_fare, bus_pct = l.bus_pct,
         fst_pax = l.fst_pax, fst_seats = l.fst_seats, fst_fare = l.fst_fare, fst_pct = l.fst_pct,
         cargo_units = l.cargo_units, cargo_cap = l.cargo_cap, cargo_rate = l.cargo_rate, cargo_pct = l.cargo_pct,
         loads_captured_at = l.loads_captured_at
   where id = p_money_id;
  return true;
end
$function$;

-- Matching money to loads (design §3.8). The statement names no flight; its time is the actual departure. On each
-- route, the airline's unmatched statement blocks (those naming exactly one route) and unmatched loads rows (whose
-- scheduled departure is known) are paired in time order, so two flights on one route never swap: a block pairs with
-- a loads row whose departure is 30 minutes after to 3 hours before it was posted, of the same aircraft where the
-- statement names one (maintenance lines do). Among the pairings, the most pairs win, then the smallest total gap,
-- which is the nearest departure when there is a choice. A block with no partner stays money-only until its loads
-- arrive, and the other way round.
create or replace function private.match_flights(p_airline_id bigint)
 returns int
 language plpgsql
 set search_path to ''
as $function$
declare
  g record; mid bigint[]; mat timestamptz[]; mreg text[]; lid bigint[]; lat timestamptz[]; lreg text[];
  n int; m int; i int; j int; w int; cnt int[]; cst bigint[]; ch smallint[];
  c_best int; k_best bigint; ch_best smallint; gap bigint; matched int := 0;
begin
  for g in
    select f.origin_code, f.dest_code from public.game_flights f
     where f.airline_id = p_airline_id and f.flight_no is null and f.posted_at is not null and f.statement_routes = 1
    intersect
    select f.origin_code, f.dest_code from public.game_flights f
     where f.airline_id = p_airline_id and f.posted_at is null and f.flight_no is not null and f.dep_at is not null
  loop
    select array_agg(f.id order by f.posted_at, f.statement_blk), array_agg(f.posted_at order by f.posted_at, f.statement_blk),
           array_agg(f.maint_registration order by f.posted_at, f.statement_blk)
      into mid, mat, mreg
      from public.game_flights f
     where f.airline_id = p_airline_id and f.flight_no is null and f.posted_at is not null and f.statement_routes = 1
       and f.origin_code = g.origin_code and f.dest_code = g.dest_code;
    select array_agg(f.id order by f.dep_at, f.flight_no, f.id), array_agg(f.dep_at order by f.dep_at, f.flight_no, f.id),
           array_agg(f.registration order by f.dep_at, f.flight_no, f.id)
      into lid, lat, lreg
      from public.game_flights f
     where f.airline_id = p_airline_id and f.posted_at is null and f.flight_no is not null and f.dep_at is not null
       and f.origin_code = g.origin_code and f.dest_code = g.dest_code;
    n := cardinality(mid); m := cardinality(lid); w := m + 1;
    -- cell (i, j), the best pairing of the first i blocks with the first j loads rows, is at i * w + j + 1
    cnt := array_fill(0, array[(n + 1) * w]);
    cst := array_fill(0::bigint, array[(n + 1) * w]);
    ch := array_fill(0::smallint, array[(n + 1) * w]);
    for i in 1 .. n loop
      for j in 1 .. m loop
        c_best := cnt[(i - 1) * w + j + 1]; k_best := cst[(i - 1) * w + j + 1]; ch_best := 1;   -- block i unpaired
        if cnt[i * w + j] > c_best or (cnt[i * w + j] = c_best and cst[i * w + j] < k_best) then   -- loads row j unpaired
          c_best := cnt[i * w + j]; k_best := cst[i * w + j]; ch_best := 2;
        end if;
        gap := extract(epoch from (mat[i] - lat[j]))::bigint;   -- posted minus scheduled, seconds
        if gap between -1800 and 10800 and (mreg[i] is null or lreg[j] is null or mreg[i] = lreg[j])
           and (cnt[(i - 1) * w + j] + 1 > c_best
                or (cnt[(i - 1) * w + j] + 1 = c_best and cst[(i - 1) * w + j] + abs(gap) <= k_best)) then
          c_best := cnt[(i - 1) * w + j] + 1; k_best := cst[(i - 1) * w + j] + abs(gap); ch_best := 3;   -- paired
        end if;
        cnt[i * w + j + 1] := c_best; cst[i * w + j + 1] := k_best; ch[i * w + j + 1] := ch_best;
      end loop;
    end loop;
    i := n; j := m;
    while i > 0 and j > 0 loop
      if ch[i * w + j + 1] = 3 then
        if private.merge_flight(mid[i], lid[j]) then matched := matched + 1; end if;
        i := i - 1; j := j - 1;
      elsif ch[i * w + j + 1] = 1 then i := i - 1;
      else j := j - 1;
      end if;
    end loop;
  end loop;
  return matched;
end
$function$;

-- Scheduled times for an airline's loads rows whose airports' offsets have become known since they were captured
create or replace function private.fill_flight_times(p_airline_id bigint)
 returns int
 language plpgsql
 set search_path to ''
as $function$
declare v_n int;
begin
  with x as (
    select f.id, t.dep_at, t.arr_at
      from public.game_flights f
      cross join lateral private.loads_times(f.world_id, f.game_date, f.dep_local, f.arr_local, f.origin_code, f.dest_code) t
     where f.airline_id = p_airline_id and f.flight_no is not null
       and (f.dep_at is null or (f.arr_at is null and f.arr_local is not null)))
  update public.game_flights f set dep_at = x.dep_at, arr_at = x.arr_at
    from x
   where f.id = x.id and x.dep_at is not null and (f.dep_at, f.arr_at) is distinct from (x.dep_at, x.arr_at);
  get diagnostics v_n = row_count;
  return v_n;
end
$function$;

-- due_at for an airline's events, once its home airport's offset is known
create or replace function private.fill_due_at(p_airline_id bigint)
 returns int
 language plpgsql
 set search_path to ''
as $function$
declare v_off int; v_n int;
begin
  select private.airport_offset_min(a.world_id, a.home_airport_code) into v_off from public.airlines a where a.id = p_airline_id;
  if v_off is null then return 0; end if;
  update public.game_events e set due_at = private.local_to_utc(e.event_date, e.event_time, v_off)
   where e.airline_id = p_airline_id and e.due_at is null;
  get diagnostics v_n = row_count;
  return v_n;
end
$function$;

-- For every airline of our groups in a world: the times that have become known, then matching. The capture does this
-- for one airline after each page; run it once for the whole world after loading the airports (#13, pull request 4).
create or replace function private.capture_refresh(p_world_id bigint)
 returns jsonb
 language plpgsql
 set search_path to ''
as $function$
declare a record; v_times int := 0; v_due int := 0; v_matched int := 0;
begin
  for a in select al.id from public.airlines al join public.groups g on g.id = al.group_id and g.world_id = al.world_id
            where al.world_id = p_world_id and g.kind = 'ours' order by al.id loop
    v_times := v_times + private.fill_flight_times(a.id);
    v_due := v_due + private.fill_due_at(a.id);
    v_matched := v_matched + private.match_flights(a.id);
  end loop;
  return jsonb_build_object('times', v_times, 'due_at', v_due, 'matched', v_matched);
end
$function$;

-- Completeness by world (design §7): a capture day is complete when every active airline of our groups in that world
-- has all five pages (statement, events, income statement, balance sheet, loads) in it. Not a count to 6.
create or replace function private.capture_day_complete(p_world_id bigint, p_day date)
 returns boolean
 language sql
 stable
 set search_path to ''
as $function$
  with ours as (
    select a.id from public.airlines a join public.groups g on g.id = a.group_id and g.world_id = a.world_id
     where a.world_id = p_world_id and a.active and g.kind = 'ours'),
  span as (select private.capture_day_start(p_world_id, p_day) as from_at)
  select exists (select 1 from ours)
     and not exists (
       select 1 from ours o, span
        where (select count(distinct r.kind) from public.game_capture_raw r
                where r.airline_id = o.id and r.kind in ('statement', 'events', 'pnl', 'balance', 'loads')
                  and r.captured_at >= span.from_at and r.captured_at < span.from_at + interval '1 day') < 5)
$function$;

-- Parses one stored page into the capture tables, using the page's own capture time throughout (so a page replayed
-- later lands exactly where it did). Statement lines go to game_statement and are folded into game_flights and
-- game_payments; loads rows go to game_flights; then money and loads are matched.
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
      insert into public.game_pnl (world_id, airline_id, airline, captured_on, capture_day, line, current_p, last_p, total_p, captured_at)
      values (r.world_id, r.airline_id, r.airline, v_today, v_day, c[1], public.as_num(c[2]), public.as_num(c[3]),
              public.as_num(c[array_length(c, 1)]), v_at)
      on conflict (airline, captured_on, line) do update set current_p = excluded.current_p, last_p = excluded.last_p,
        total_p = excluded.total_p, capture_day = excluded.capture_day;
      n := n + 1;
    end loop;

  elsif r.kind = 'balance' then
    v_day := private.capture_day(r.world_id, v_at);
    for row_ in select * from jsonb_array_elements(r.rows) loop
      c := array(select jsonb_array_elements_text(row_));
      if array_length(c, 1) >= 3 and c[1] ~ '^\d{3,4}$' then
        insert into public.game_balance (world_id, airline_id, airline, captured_on, capture_day, account, amount, captured_at)
        values (r.world_id, r.airline_id, r.airline, v_today, v_day, c[1] || ' ' || c[2], public.as_num(c[3]), v_at)
        on conflict (airline, captured_on, account) do update set amount = excluded.amount, capture_day = excluded.capture_day;
        n := n + 1;
      end if;
      if array_length(c, 1) >= 6 and c[4] ~ '^\d{3,4}$' then
        insert into public.game_balance (world_id, airline_id, airline, captured_on, capture_day, account, amount, captured_at)
        values (r.world_id, r.airline_id, r.airline, v_today, v_day, c[4] || ' ' || c[5], public.as_num(c[6]), v_at)
        on conflict (airline, captured_on, account) do update set amount = excluded.amount, capture_day = excluded.capture_day;
        n := n + 1;
      end if;
    end loop;
  end if;
  return jsonb_build_object('ok', true, 'kind', r.kind, 'rows', n);
end
$function$;

-- The loads step, as today: the last 3 days of an airline's captured loads into planner_loads (economy load per
-- flight, keyed "Airline|number"), the month's saved_at moved on. A day is done once its capture day is complete for
-- the whole world (not when 6 airlines are in), and a day already done stays done, as it always has.
create or replace function private.apply_loads_from_capture(p_airline_id bigint)
 returns jsonb
 language plpgsql
 set search_path to ''
as $function$
declare d record; mon text; cur jsonb; day jsonb; f jsonb; n int := 0; v_name text; v_world bigint;
  ms bigint := (extract(epoch from clock_timestamp()) * 1000)::bigint;
begin
  select coalesce(a.planner_name, a.public_name, a.game_name, a.game_id::text), a.world_id into v_name, v_world from public.airlines a where a.id = p_airline_id;
  for d in select distinct g.game_date from public.game_flights g
            where g.airline_id = p_airline_id and g.flight_no is not null and g.game_date >= current_date - 3 loop
    mon := to_char(d.game_date, 'YYYY-MM');
    select pl.json::jsonb into cur from public.planner_loads pl where pl.month = mon for update;
    cur := coalesce(cur, '{}'::jsonb);
    day := coalesce(cur -> (d.game_date::text), '{}'::jsonb);
    select coalesce(jsonb_object_agg(v_name || '|' || g.flight_no::text, g.eco_pct), '{}'::jsonb) into f
      from public.game_flights g
     where g.airline_id = p_airline_id and g.flight_no is not null and g.game_date = d.game_date and g.eco_pct is not null;
    day := jsonb_set(day, '{f}', coalesce(day -> 'f', '{}'::jsonb) || f, true);
    day := day || jsonb_build_object('done', coalesce(day -> 'done' = 'true'::jsonb, false)
                                             or private.capture_day_complete(v_world, d.game_date),
                                     'captured', now(), 'source', 'capture');
    cur := jsonb_set(cur, array[d.game_date::text], day, true);
    -- saved_at moves on, so a browser holding an older copy of the month takes this one when it next loads
    insert into public.planner_loads (month, json, saved_at) values (mon, cur::text, ms)
      on conflict (month) do update set json = excluded.json, saved_at = excluded.saved_at;
    n := n + 1;
  end loop;
  return jsonb_build_object('days', n);
end
$function$;

-- Stores one page for an airline of the key's world and parses it, all at one capture time: capture_ingest() calls it
-- with now(); a test replays saved pages with their own times. Pages for an airline outside the world are refused.
create or replace function private.capture_store(p_world_id bigint, p_airline text, p_kind text, p_page text, p_rows jsonb,
                                                 p_at timestamptz, p_loads_step boolean default true)
 returns jsonb
 language plpgsql
 set search_path to ''
as $function$
declare v_al bigint; v_name text; v_rid bigint; v_res jsonb; v_day date;
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
  return v_res || jsonb_build_object('capture_day', v_day, 'day_complete', private.capture_day_complete(p_world_id, v_day));
end
$function$;

-- The entry point, same name and arguments as before, so today's userscript keeps working. The key says the world.
create or replace function public.capture_ingest(p_key text, p_airline text, p_kind text, p_page text, p_rows jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_world bigint;
begin
  v_world := private.capture_key_world(p_key);
  if v_world is null then return jsonb_build_object('ok', false, 'error', 'bad key'); end if;
  if p_kind is null or p_kind not in ('statement', 'events', 'loads', 'pnl', 'balance', 'html') then
    return jsonb_build_object('ok', false, 'error', 'bad kind');
  end if;
  perform set_config('equinox.actor', 'capture', true);
  delete from public.game_capture_raw where captured_at < now() - interval '14 days';   -- raw pages kept 14 days
  return private.capture_store(v_world, p_airline, p_kind, p_page, p_rows, now());
end
$function$;

-- What the userscript captures: the key's world and its active airlines of our groups, in display order
create or replace function public.capture_airlines(p_key text)
 returns jsonb
 language plpgsql
 stable
 security definer
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
                  where a.world_id = v_world and a.active and g.kind = 'ours'));
end
$function$;

-- Retired (the removal file stops authenticated calling them); kept so a call from postgres still works
create or replace function public.parse_capture(p_id bigint)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
begin
  return private.capture_page(p_id);
end
$function$;

create or replace function public.apply_loads_from_capture(p_airline text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_al bigint;
begin
  select a.id into v_al from public.airlines a join public.worlds w on w.id = a.world_id and w.is_default
   where a.planner_name = p_airline;
  if v_al is null then return jsonb_build_object('days', 0); end if;
  return private.apply_loads_from_capture(v_al);
end
$function$;

-- ============================================================ 5. the backfill (§9 step 2)
-- 5a. one game_flights row per loads row. The flight number is the code's number: every code so far is the airline's
-- code, a space and a number, which the game_loads view gives back exactly (checked here and by the rehearsal).
do $codes$
declare bad bigint;
begin
  select count(*) into bad
    from public.game_loads l
    join public.airlines a on a.planner_name = l.airline
    join public.worlds w on w.id = a.world_id and w.is_default
   where l.code is distinct from a.iata_code || ' ' || (substring(l.code from '^[A-Z0-9]{2,3}\s?(\d{1,5})'))::int;
  if bad > 0 then
    raise exception 'capture data: % loads rows have a code that isn''t the airline''s code and a number', bad;
  end if;
end
$codes$;

insert into public.game_flights (world_id, airline_id, game_date, flight_no, origin_code, dest_code, dep_local, arr_local,
       registration, status, eco_pax, eco_seats, eco_fare, eco_pct, bus_pax, bus_seats, bus_fare, bus_pct, fst_pax,
       fst_seats, fst_fare, fst_pct, cargo_units, cargo_cap, cargo_rate, cargo_pct, loads_captured_at)
select a.world_id, a.id, l.flight_date, (substring(l.code from '^[A-Z0-9]{2,3}\s?(\d{1,5})'))::int, l.origin, l.dest,
       l.dep_time, l.arr_time, l.tail, l.status, l.eco_pax, l.eco_seats, l.eco_fare, l.eco, l.bus_pax, l.bus_seats,
       l.bus_fare, l.bus, l.fst_pax, l.fst_seats, l.fst_fare, l.fst, l.cargo_units, l.cargo_cap, l.cargo_rate, l.cargo,
       l.captured_at
  from public.game_loads l
  join public.airlines a on a.planner_name = l.airline
  join public.worlds w on w.id = a.world_id and w.is_default;

-- 5b. every statement line since 6 Oct folded into flights and payments, airline by airline; then the times that are
-- known and matching (nothing matches until the airports' offsets are loaded, #13 pull request 4)
do $money$
declare a record; v_lines bigint; v_tied bigint; v_paid bigint;
begin
  for a in select distinct s.airline_id from public.game_statement s order by 1 loop
    perform private.fold_statement(a.airline_id,
                                   array(select distinct s.ts from public.game_statement s where s.airline_id = a.airline_id));
  end loop;
  -- every statement line is now in exactly one place: a flight's money or a payment
  select count(*), count(*) filter (where flight_id is not null) into v_lines, v_tied from public.game_statement;
  select count(*) into v_paid from public.game_payments;
  if v_lines <> v_tied + v_paid then
    raise exception 'capture data: % statement lines, but % tied to flights and % payments', v_lines, v_tied, v_paid;
  end if;
  perform private.capture_refresh(w.id) from public.worlds w;
end
$money$;

-- ============================================================ 6. game_loads becomes a view; the compatibility views (§3.12, §3.13)
-- The table keeps its rows under a new name until #18; the view takes its name in the same transaction, so nothing
-- ever sees neither.
alter table public.game_loads rename to game_loads_before_13;

create view public.game_loads with (security_invoker = true) as
select al.planner_name as airline, f.game_date as flight_date, al.iata_code || ' ' || f.flight_no as code,
       f.dep_local as dep_time, f.registration as tail, f.origin_code as origin, f.dest_code as dest, f.arr_local as arr_time,
       f.eco_pct::numeric as eco, f.bus_pct::numeric as bus, f.fst_pct::numeric as fst, f.cargo_pct::numeric as cargo,
       f.status, f.loads_captured_at as captured_at,
       f.eco_pax, f.eco_seats, trim_scale(f.eco_fare) as eco_fare, f.bus_pax, f.bus_seats, trim_scale(f.bus_fare) as bus_fare,
       f.fst_pax, f.fst_seats, trim_scale(f.fst_fare) as fst_fare, f.cargo_units, f.cargo_cap,
       trim_scale(f.cargo_rate) as cargo_rate
  from public.game_flights f
  join public.airlines al on al.id = f.airline_id
 where f.flight_no is not null;

-- One row per statement block, as before: each flight's money, plus the payments the old view counted with flights
-- (everything but leases, the week-end closing, deposits, purchases, cabins and configurations, so salaries are in,
-- as they always were), in the block the statement posted them in
create or replace view public.game_flight_pnl with (security_invoker = true) as
with money as (
  select f.airline_id, f.posted_at as ts, f.statement_blk::int as blk, f.statement_routes::int as routes_n,
         case when f.statement_routes > 0 then f.origin_code || '-' || f.dest_code end as route,
         f.statement_pax as pax, f.maint_registration as tail, f.pax_income, f.cargo_income, f.fuel, f.onboard,
         f.handling, f.landing, f.atc, f.maintenance, f.income_total as income, f.cost_total as costs
    from public.game_flights f
   where f.posted_at is not null
  union all
  select p.airline_id, p.paid_at, p.statement_blk::int, 0, null, null, null, null, null, null, null, null, null, null,
         null, case when p.side = 'C' then p.amount else 0 end, case when p.side = 'C' then 0 else p.amount end
    from public.game_payments p
   where coalesce(p.statement_blk, 1) > 0
     and p.descr not ilike 'Leasing rate%' and p.descr not ilike 'Week-end closing%' and p.descr not ilike '%deposit%'
     and p.descr not ilike '%purchase%' and p.descr not ilike '%cabin%' and p.descr not ilike '%configuration%')
select al.planner_name as airline, m.ts, m.blk,
       max(m.route) as route, coalesce(max(m.routes_n), 0)::bigint as routes_n, max(m.pax) as pax, max(m.tail) as tail,
       trim_scale(coalesce(sum(m.pax_income), 0)) as pax_income, trim_scale(coalesce(sum(m.cargo_income), 0)) as cargo_income,
       trim_scale(coalesce(sum(m.fuel), 0)) as fuel, trim_scale(coalesce(sum(m.onboard), 0)) as onboard,
       trim_scale(coalesce(sum(m.handling), 0)) as handling, trim_scale(coalesce(sum(m.landing), 0)) as landing,
       trim_scale(coalesce(sum(m.atc), 0)) as atc, trim_scale(coalesce(sum(m.maintenance), 0)) as maintenance,
       trim_scale(sum(m.income) - sum(m.costs)) as profit
  from money m
  join public.airlines al on al.id = m.airline_id
 group by m.airline_id, al.planner_name, m.ts, m.blk;

-- Each airline's last 24 hours before its latest statement line, as before: flights, income, costs and hours
create or replace view public.game_ops_recent with (security_invoker = true) as
with money as (
  select f.airline_id, f.posted_at as ts, f.income_total as income, f.cost_total as costs,
         (f.pax_income is not null)::int as flights
    from public.game_flights f
   where f.posted_at is not null
  union all
  select p.airline_id, p.paid_at, case when p.side = 'C' then p.amount else 0 end,
         case when p.side = 'C' then 0 else p.amount end, 0
    from public.game_payments p
   where p.descr not ilike 'Leasing rate%' and p.descr not ilike 'Week-end closing%' and p.descr not ilike '%deposit%'
     and p.descr not ilike '%purchase%' and p.descr not ilike '%cabin%' and p.descr not ilike '%configuration%'),
last as (
  select x.airline_id, max(x.ts) as lt
    from (select f.airline_id, f.posted_at as ts from public.game_flights f where f.posted_at is not null
          union all
          select p.airline_id, p.paid_at from public.game_payments p) x
   group by x.airline_id),
w as (
  select m.airline_id, m.ts, m.income, m.costs, m.flights, l.lt
    from money m join last l on l.airline_id = m.airline_id
   where m.ts > l.lt - interval '24 hours')
select al.planner_name as airline, max(w.lt) as last_ts, sum(w.flights)::bigint as flights,
       trim_scale(coalesce(sum(w.income), 0)) as income, trim_scale(coalesce(sum(w.costs), 0)) as costs,
       round(extract(epoch from (max(w.lt) - min(w.ts))) / 3600::numeric, 1) as hours
  from w
  join public.airlines al on al.id = w.airline_id
 group by w.airline_id, al.planner_name;

-- ============================================================ 7. export_capture(): exactly what it returned before
create or replace function public.export_capture(p_secret text, p_days integer default 8)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
begin
  if not exists (select 1 from public.ingest_secret where secret = p_secret) then raise exception 'not allowed'; end if;
  return jsonb_build_object(
    'pnl', (select coalesce(jsonb_agg(to_jsonb(f)), '[]'::jsonb) from public.game_flight_pnl f
             where f.ts >= now() - make_interval(days => p_days)),
    'loads', (select coalesce(jsonb_agg(to_jsonb(l) - 'captured_at'), '[]'::jsonb) from public.game_loads l
               where l.flight_date >= current_date - (p_days + 1)),
    -- the columns #13 added stay out, so the scripts get what they always got
    'events', (select coalesce(jsonb_agg(to_jsonb(e) - array['captured_at', 'world_id', 'airline_id', 'due_at']), '[]'::jsonb)
                 from public.game_events e where e.event_date >= current_date - p_days),
    'balance', (select coalesce(jsonb_agg(to_jsonb(b) - array['world_id', 'airline_id', 'capture_day']), '[]'::jsonb)
                  from public.game_balance b where b.account like '2800%' and b.captured_on >= current_date - p_days),
    'ops', (select coalesce(jsonb_agg(to_jsonb(o)), '[]'::jsonb) from public.game_ops_recent o),
    'runs', (select coalesce(jsonb_agg(jsonb_build_object('airline', r.airline, 'kind', r.kind, 'captured_at', r.captured_at)), '[]'::jsonb)
               from public.game_capture_raw r where r.captured_at >= now() - make_interval(days => p_days) and r.kind <> 'html'));
end
$function$;

-- ============================================================ 8. access (§5)
-- game_flights and game_payments: staff read them, nobody else; only the capture's functions (as owner) write them.
-- The view game_loads is new, so it starts closed; game_flight_pnl and game_ops_recent keep their grants (select for
-- authenticated, nothing for anon).
alter table public.game_flights enable row level security;
alter table public.game_payments enable row level security;
create policy "staff read" on public.game_flights for select to authenticated using ((select public.is_planner_user()));
create policy "staff read" on public.game_payments for select to authenticated using ((select public.is_planner_user()));
revoke all on table public.game_flights, public.game_payments, public.game_loads from public, anon, authenticated;
grant select on table public.game_flights, public.game_payments, public.game_loads to authenticated;

revoke all on function private.capture_day_start(bigint, date), private.capture_day(bigint, timestamptz),
  private.airport_offset_min(bigint, text), private.local_to_utc(date, text, int),
  private.loads_times(bigint, date, text, text, text, text), private.statement_category(text),
  private.payment_kind(text), private.is_payment_line(text, int), private.payment_registration(text),
  private.capture_find_airline(bigint, text), private.capture_key_world(text),
  private.statement_blocks(bigint, timestamptz[]), private.fold_statement(bigint, timestamptz[]),
  private.merge_flight(bigint, bigint), private.match_flights(bigint), private.fill_flight_times(bigint),
  private.fill_due_at(bigint), private.capture_refresh(bigint), private.capture_day_complete(bigint, date),
  private.capture_page(bigint), private.apply_loads_from_capture(bigint),
  private.capture_store(bigint, text, text, text, jsonb, timestamptz, boolean)
  from public, anon, authenticated;
-- the userscript asks for its airlines with the capture key, like capture_ingest()
revoke all on function public.capture_airlines(text) from public, anon, authenticated;
grant execute on function public.capture_airlines(text) to anon, authenticated;

-- ============================================================ 9. descriptions (decision #10)
comment on function private.capture_day_start(bigint, date) is 'When a world''s capture day starts, in UTC: the day plus the setting capture_day_starts_utc (10:00 until it is set), design §2.';
comment on function private.capture_day(bigint, timestamptz) is 'The capture day a moment belongs to (design §2): the UTC date of the moment minus capture_day_starts_utc (10:00 until set), so one evening''s capture is one day, named after the evening.';
comment on function private.airport_offset_min(bigint, text) is 'An airport''s UTC offset in a world, in minutes: coalesce(world_airports.utc_offset_override, airports.utc_offset). Null while it isn''t known (the airports are loaded by #13''s pull request 4).';
comment on function private.local_to_utc(date, text, integer) is 'A local date and clock time ("07:30") at a fixed offset in minutes, as a moment. Null if any part is missing.';
comment on function private.loads_times(bigint, date, text, text, text, text) is 'A loads row''s scheduled departure and arrival as moments, from the local times and the airports'' offsets (design §3.8, §4): arrival is departure plus the block worked out from the local times. Null while an offset isn''t known.';
comment on function private.statement_category(text) is 'The type of a bank-statement line (pax_income, cargo_income, fuel, onboard, handling, landing, atc, maintenance or other), as game_flight_pnl has always counted them.';
comment on function private.payment_kind(text) is 'The kind of a statement line that isn''t tied to a flight (game_payments.kind): lease, salaries ("Payment of employee salaries", the week-end closing), deposit, purchase, refit (a configuration), cabin, or other.';
comment on function private.is_payment_line(text, integer) is 'True for a statement line that never belongs to a flight: a lease, salaries, a deposit, a purchase, a refit or a cabin, or a line the parser put in block 0.';
comment on function private.payment_registration(text) is 'The aircraft a payment names, e.g. B-0161 from "Leasing rate for B-0161". Null when it names none.';
comment on function private.capture_find_airline(bigint, text) is 'The airline a capture page is for, among the airlines of our groups in the key''s world: by the game''s ID (the userscript from version 1.3), or by name as the older userscript and the bookmark send it (the names matched since 7 Oct). Null when none or more than one fits, so the page is refused.';
comment on function private.capture_key_world(text) is 'The world a capture key belongs to (capture_keys.world_id), or null for a key that doesn''t match.';
comment on function private.statement_blocks(bigint, timestamp with time zone[]) is 'An airline''s statement lines in the given minutes, grouped by minute and block (blk) as game_flight_pnl has always grouped them, leaving out payments: money by type, the route, passengers, the maintenance line''s aircraft, and whether the block is a flight (any flight line or route) or only payments.';
comment on function private.fold_statement(bigint, timestamp with time zone[]) is 'Folds an airline''s statement lines in the given minutes into game_flights (one row per flight block, matched by minute and block) and game_payments (every other line), and ties each flight line to its flight (game_statement.flight_id). Blocks that changed since are taken apart and folded again; a flight already matched keeps its loads. Run after every statement page, and by the backfill for every minute.';
comment on function private.merge_flight(bigint, bigint) is 'Joins one money-only game_flights row and one loads-only row into one flight: the loads columns move into the money row, and the loads row goes.';
comment on function private.match_flights(bigint) is 'Matches an airline''s money-only and loads-only game_flights rows (design §3.8): per route, in time order so two flights on one route never swap, a block pairs with a loads row whose scheduled departure is 30 minutes after to 3 hours before the statement time, of the same aircraft where the statement names one; the most pairs win, then the smallest total gap. Unpaired rows wait for their partner. Needs the airports'' offsets.';
comment on function private.fill_flight_times(bigint) is 'Fills an airline''s loads rows'' dep_at and arr_at where the airports'' offsets have become known since they were captured.';
comment on function private.fill_due_at(bigint) is 'Fills an airline''s game_events.due_at once its home airport''s offset is known.';
comment on function private.capture_refresh(bigint) is 'For every airline of our groups in a world: fills flight times and events'' due_at that have become known, then matches money to loads. Run once after the airports are loaded (#13, pull request 4); the capture does the same for one airline after each page.';
comment on function private.capture_day_complete(bigint, date) is 'Completeness by world (design §7): true when every active airline of our groups in that world has all five pages (statement, events, income statement, balance sheet, loads) in that capture day. Not a count to 6, so a 7th airline must be captured too.';
comment on function private.capture_page(bigint) is 'Parses one stored capture page into the capture tables, using the page''s own capture time throughout: statement lines into game_statement, folded into game_flights and game_payments; events into game_events (with due_at where known); loads into game_flights; the income statement and balance sheet into game_pnl and game_balance (with capture_day). Then money and loads are matched.';
comment on function private.apply_loads_from_capture(bigint) is 'The loads step, as before: the last 3 days of an airline''s captured loads into planner_loads (economy load per flight, keyed "Airline|number") and the month''s saved_at moved on, so browsers pick them up. A day is done once its capture day is complete for the whole world (private.capture_day_complete), and a day already done stays done.';
comment on function private.capture_store(bigint, text, text, text, jsonb, timestamp with time zone, boolean) is 'Stores one page for an airline of the given world and parses it, at the given capture time, and says whether that capture day is now complete. Refuses a page for an airline outside the world. capture_ingest() calls it with now(); the tests replay saved pages with their own times.';

comment on function public.capture_ingest(text, text, text, text, jsonb) is 'Entry point for the in-game capture. Checks the capture key, which belongs to one world; finds the airline by the game''s ID or, from older userscripts, by name, and refuses one outside the key''s world; keeps the raw page 14 days and parses it (private.capture_page): bank statement into game_flights and game_payments, loads into game_flights, and planner_loads as before. Answers with the capture day and whether it is complete.';
comment on function public.capture_airlines(text) is 'For the capture userscript, with the capture key: the key''s world and its active airlines of our groups (game ID, name, code), in display order, so the userscript doesn''t keep its own list.';
comment on function public.export_capture(text, integer) is 'Exports recent capture data for Claude''s scripts, exactly as before #13: profit per flight, loads, payments ahead, cash, the last 24 hours and capture runs, from the compatibility views. Needs the ingest secret.';
comment on function public.parse_capture(bigint) is 'Retired by #13 (pull request 3): the parsing is private.capture_page(), which this now calls. No longer callable by signed-in accounts once 20261009230100_capture_data_removals.sql has run; kept until #18.';
comment on function public.apply_loads_from_capture(text) is 'Retired by #13 (pull request 3): the loads step is private.apply_loads_from_capture(), which this now calls for the default world''s airline of that name. No longer callable by signed-in accounts once 20261009230100_capture_data_removals.sql has run; kept until #18.';

comment on table public.game_flights is 'One row per flown flight (decision #16, design §3.8): its loads from the loads page and its money from the bank statement, matched by route and time. Until a block and a loads row are matched (or when one never comes), a row holds only one side: money-only rows have no flight number, loads-only rows no statement time. Written by the capture (private.capture_page); read through game_loads and game_flight_pnl. Kept one full calendar month, then archived.';
comment on table public.game_payments is 'Bank-statement lines not tied to a flight: leases, salaries, purchases, deposits, cabins, refits, and lines in a minute with no flight. One row per statement line. Written by the capture (private.fold_statement). Kept for good.';

comment on column public.game_flights.game_date is 'The local date at departure, as the loads page shows it';
comment on column public.game_flights.flight_no is 'From the loads page, e.g. 1001 (shown as KF 1001); null on a money-only row, since the statement names no flight';
comment on column public.game_flights.dep_local is 'Departure, local clock time as the game shows it, e.g. 07:30';
comment on column public.game_flights.arr_local is 'Arrival, local clock time as the game shows it';
comment on column public.game_flights.dep_at is 'Scheduled departure, from the local time and the origin''s offset (null while the offset isn''t known); on a money-only row, the statement time';
comment on column public.game_flights.arr_at is 'Scheduled arrival: departure plus the block from the local times (null while an offset isn''t known)';
comment on column public.game_flights.posted_at is 'The statement''s time for the flight, its actual departure, UTC; null on a loads-only row';
comment on column public.game_flights.statement_blk is 'The statement''s block number in that minute (game_statement.blk)';
comment on column public.game_flights.statement_routes is 'How many routes the block''s lines name; 1 for a normal flight, and only those are matched to loads';
comment on column public.game_flights.route_id is 'The route, once routes are loaded (#13, pull request 4)';
comment on column public.game_flights.aircraft_id is 'The aircraft, once aircraft are loaded (#13, pull request 4)';
comment on column public.game_flights.registration is 'The aircraft as the loads page names it';
comment on column public.game_flights.maint_registration is 'The aircraft named by the statement''s maintenance line (only some flights have one): game_flight_pnl.tail';
comment on column public.game_flights.status is 'As the loads page shows it: finished or inflight so far';
comment on column public.game_flights.eco_pct is 'Economy load, percent, as the game shows it (bus_pct, fst_pct and cargo_pct likewise). Stored, not worked out: the game''s cargo figure differs from units ÷ capacity on some flights';
comment on column public.game_flights.eco_fare is 'AS$ (bus_fare, fst_fare and cargo_rate likewise)';
comment on column public.game_flights.pax_income is 'AS$, from the statement (cargo_income, fuel, onboard, handling, landing, atc and maintenance likewise); null when the block has no such line';
comment on column public.game_flights.income_total is 'Every line of the block on the income side, AS$';
comment on column public.game_flights.cost_total is 'Every line of the block on the cost side, AS$';
comment on column public.game_flights.profit is 'income_total − cost_total, AS$';
comment on column public.game_flights.statement_pax is 'Passengers named on the statement (passenger handling)';
comment on column public.game_flights.loads_captured_at is 'When the loads page last wrote the row';
comment on column public.game_flights.money_captured_at is 'When the block''s newest statement line was first captured';
comment on column public.game_payments.paid_at is 'The statement''s time, UTC';
comment on column public.game_payments.kind is 'lease, salaries, purchase, deposit, cabin, refit or other';
comment on column public.game_payments.registration is 'The aircraft the line names, e.g. from "Leasing rate for B-0161"';
comment on column public.game_payments.aircraft_id is 'The aircraft, once aircraft are loaded (#13, pull request 4)';
comment on column public.game_payments.amount is 'AS$';
comment on column public.game_payments.side is 'D for a cost, C for income';
comment on column public.game_payments.occ is 'Tells apart identical lines posted in the same minute';
comment on column public.game_payments.statement_blk is 'The statement''s block number (game_statement.blk), so game_flight_pnl and game_ops_recent count the payments they always counted (salaries) where they always did';

comment on table public.game_statement is 'Bank-statement lines from the capture, as the game lists them. Each line is folded into a flight (flight_id) in game_flights or into game_payments. Kept 14 days for checking, once the clean-up is switched on (#13, pull request 7). Written by the capture (private.capture_page).';
comment on column public.game_statement.flight_id is 'The game_flights row the line was folded into; null for a payment (game_payments)';
comment on table public.game_events is 'Payments the game lists ahead on the events page: leases, salaries and deliveries. Written by the capture (private.capture_page). Read by the planner''s cash forecast (Review: Cash, next 14 days), which also takes each type''s lease from here.';
comment on column public.game_events.due_at is 'When it falls due, from the local time at the airline''s home airport; null while that airport''s offset isn''t known (filled once the airports are loaded)';
comment on table public.game_balance is 'The balance-sheet page from the nightly capture: one row per airline, account and UTC date. Account 2800 is cash. Written by the capture (private.capture_page). Read by the planner (Review: the group today, Cash next 14 days) and export_capture().';
comment on column public.game_balance.captured_on is 'The UTC date of the capture, as the old planner reads it (an evening''s capture can fall on the next UTC date)';
comment on column public.game_balance.capture_day is 'The capture day (design §2): the evening of the capture that last wrote the row';
comment on table public.game_pnl is 'The game''s income statement per airline and UTC date, for the current, last and total periods. Written by the capture (private.capture_page). Not read by any screen yet; kept for reports.';
comment on column public.game_pnl.capture_day is 'The capture day (design §2): the evening of the capture that last wrote the row';
comment on table public.game_capture_raw is 'Every page the capture sent, as rows of cells before parsing, with its world and airline. Kept 14 days. Written by capture_ingest(). Read by private.capture_page(), completeness (private.capture_day_complete) and the planner''s Capture board.';
comment on table public.capture_keys is 'Hashed keys that let the in-game capture send data. Only hashes are stored. Each key belongs to one world (world_id): a page for an airline outside it is refused. Written by hand when a key is issued. Read by capture_ingest() and capture_airlines().';
comment on column public.capture_keys.world_id is 'The world the key captures; name it when issuing a key';
comment on table public.game_loads_before_13 is 'Retired by #13 (pull request 3): the loads table as it stood when its rows moved into game_flights. Nothing writes or reads it; the name game_loads is now a view. Kept so a revert can put it back, until #18.';

comment on view public.game_loads is 'Today''s game_loads, from game_flights: every captured flight with passengers, seats, fares and loads by class and cargo, in the columns the planner (Check: daily load report, growth signals; Review: fare changes) and export_capture() read. Shows the caller only what it may read.';
comment on view public.game_flight_pnl is 'Each statement block''s income and costs by type and its profit, as before #13, from game_flights and the payments the old view counted with flights (salaries). Read by the planner (Review: route profit, aircraft) and export_capture(). Shows the caller only what it may read.';
comment on view public.game_ops_recent is 'Each airline''s last 24 hours before its latest statement line, as before #13: flights, income, costs and hours, from game_flights and game_payments. Read by the planner (Review: the group today; the cash forecast''s flight profit) and export_capture(). Shows the caller only what it may read.';

select set_config('equinox.change_log', '', true), set_config('equinox.actor', '', true),
       set_config('equinox.actor_detail', '', true);

-- The planner's data in proper tables, empty apart from the reference rows (decision #13, build pull request 2).
-- Design: docs/design/2026-10-09-data-model.md (§3.1 to §3.7, §3.12, §5, §6, §9 step 1). Spec:
-- docs/specs/2026-10-09-new-tables.md.
--
-- Adds only; changes nothing that exists:
--   1. the private schema, which the data API doesn't expose, holding the trigger functions and helpers;
--   2. 32 planner tables and change_log, each with RLS on and one staff rule per action;
--   3. the change log: one trigger function, private.log_change(), on every planner table, and private.restore_row();
--   4. the views flight_legs_local and flight_no_clashes, both security_invoker;
--   5. grants: anon gets nothing; authenticated reads every new table and view, and writes the planner tables (not
--      change_log, which stays read-only to it). Each new object is revoked first, so it is closed whatever the
--      database's defaults (live still gives anon and authenticated everything by default until Gitesh runs
--      20261009210100_default_privileges.sql);
--   6. the reference rows: the world Gander, the group equinox. and our six airlines (and the codes of their six home
--      airports, which the airlines point at).
-- Nothing reads or writes these tables yet: the capture moves in with pull request 3, the planner's data with 4.

-- ============================================================ 1. the private schema
create schema if not exists private;
revoke all on schema private from public;
comment on schema private is 'Internal steps the data API doesn''t expose (decision #13, design §5): the planner tables'' trigger functions and helpers. Only the database itself and postgres use them.';

-- ============================================================ 2. helper and trigger functions
-- days_utc on flight_legs and plan_card_legs: ISO weekdays, sorted, no repeats, 1 to 7, at least one (design §4)
create or replace function private.is_weekday_set(p_days smallint[])
 returns boolean
 language sql
 immutable
 parallel safe
 set search_path to ''
as $function$
  select p_days is not null
     and cardinality(p_days) between 1 and 7
     and array_ndims(p_days) = 1
     and p_days = array(select distinct d from unnest(p_days) as d where d between 1 and 7 order by d)
$function$;

-- created_at and updated_at: updated_at moves only when a row is added or really changes
create or replace function private.set_updated_at()
 returns trigger
 language plpgsql
 set search_path to ''
as $function$
begin
  if tg_op = 'INSERT' then
    new.updated_at := now();
  elsif (to_jsonb(new) - 'updated_at') is distinct from (to_jsonb(old) - 'updated_at') then
    new.updated_at := now();
  else
    new.updated_at := old.updated_at;   -- an update that changes nothing leaves the row as it was
  end if;
  return new;
end
$function$;

-- flight_legs: leg 1 flies hub -> destination, leg 2 destination -> hub, matching the leg's route (design §3.4)
create or replace function private.check_leg_route()
 returns trigger
 language plpgsql
 set search_path to ''
as $function$
declare r record;
begin
  select ro.hub_code, ro.dest_code into r
    from public.rotations rot join public.routes ro on ro.id = rot.route_id
   where rot.id = new.rotation_id;
  -- no rotation found: the foreign key refuses a rotation that doesn't exist, and the access rules refuse a caller who
  -- can't read it
  if not found then return new; end if;
  if (new.leg_no = 1 and (new.origin_code, new.dest_code) is distinct from (r.hub_code, r.dest_code))
     or (new.leg_no = 2 and (new.origin_code, new.dest_code) is distinct from (r.dest_code, r.hub_code)) then
    raise exception 'flight leg % of rotation % flies % to %, but its route is % to % (leg 1 leaves the hub, leg 2 returns to it)',
      new.leg_no, new.rotation_id, new.origin_code, new.dest_code, r.hub_code, r.dest_code
      using errcode = 'check_violation';
  end if;
  return new;
end
$function$;

-- routes and rotations: changing a route's airports, or a rotation's route, mustn't leave its legs not matching
create or replace function private.check_route_legs()
 returns trigger
 language plpgsql
 set search_path to ''
as $function$
declare bad bigint;
begin
  select l.id into bad
    from public.flight_legs l
    join public.rotations rot on rot.id = l.rotation_id
    join public.routes ro on ro.id = rot.route_id
   where (case when tg_table_name = 'routes' then ro.id else rot.id end) = new.id
     and ((l.leg_no = 1 and (l.origin_code, l.dest_code) is distinct from (ro.hub_code, ro.dest_code))
       or (l.leg_no = 2 and (l.origin_code, l.dest_code) is distinct from (ro.dest_code, ro.hub_code)))
   limit 1;
  if bad is not null then
    raise exception 'this change to % % would leave flight leg % not matching its route', tg_table_name, new.id, bad
      using errcode = 'check_violation';
  end if;
  return null;
end
$function$;

-- The change log (design §6, decision #15). Runs as owner (postgres) so it can write change_log, which stays
-- read-only to everyone else.
create or replace function private.log_change()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  -- the role the change was made as: authenticated through the data API, postgres for Claude, jobs and migrations
  v_role text := coalesce(nullif(current_setting('role', true), 'none'), session_user);
  v_oldrow jsonb;
  v_newrow jsonb;
  v_old jsonb;
  v_new jsonb;
  v_key jsonb;
  v_world bigint;
  v_actor text := nullif(current_setting('equinox.actor', true), '');
  v_detail text := nullif(current_setting('equinox.actor_detail', true), '');
begin
  -- the data load switches logging off; honoured only for postgres, so the website and planner can't
  if current_setting('equinox.change_log', true) = 'off' and session_user = 'postgres' and v_role = 'postgres' then
    return null;
  end if;
  if tg_op <> 'INSERT' then v_oldrow := to_jsonb(old); end if;
  if tg_op <> 'DELETE' then v_newrow := to_jsonb(new); end if;
  if tg_op = 'UPDATE' then
    -- only the columns that changed, ignoring updated_at; nothing at all when nothing changed
    select jsonb_object_agg(n.key, v_oldrow -> n.key), jsonb_object_agg(n.key, n.value)
      into v_old, v_new
      from jsonb_each(v_newrow) as n
     where n.key <> 'updated_at' and n.value is distinct from (v_oldrow -> n.key);
    if v_new is null then return null; end if;
  else
    v_old := v_oldrow;   -- a delete keeps the whole old row
    v_new := v_newrow;   -- an insert keeps the whole new row
  end if;
  -- the row's primary key, e.g. {"id": 812}
  select jsonb_object_agg(a.attname, coalesce(v_newrow, v_oldrow) -> a.attname::text)
    into v_key
    from pg_catalog.pg_index i
    cross join lateral unnest(i.indkey::smallint[]) as k(attnum)
    join pg_catalog.pg_attribute a on a.attrelid = i.indrelid and a.attnum = k.attnum
   where i.indrelid = tg_relid and i.indisprimary;
  v_world := (coalesce(v_newrow, v_oldrow) ->> (case when tg_table_name = 'worlds' then 'id' else 'world_id' end))::bigint;
  -- who: whatever the writer named for its transaction; if nothing, planner for a signed-in user, otherwise unset
  if v_actor is null then
    v_actor := case when auth.uid() is not null then 'planner' else 'unset' end;
  elsif v_actor not in ('planner', 'claude', 'capture', 'script', 'job', 'migration', 'unset') then
    v_detail := concat_ws(' · ', 'named itself ' || v_actor, v_detail);   -- nothing is refused
    v_actor := 'unset';
  end if;
  insert into public.change_log (world_id, table_name, row_key, op, old_values, new_values, actor, actor_detail, db_role, txid)
  values (v_world, tg_table_name, v_key, lower(tg_op), v_old, v_new, v_actor, v_detail, v_role, pg_catalog.txid_current());
  return null;
end
$function$;

-- ============================================================ 3. the tables
-- Types follow design §3: ids are bigint identity; world_id is not null; codes are text; *_on dates; *_at timestamptz;
-- *_min smallint; *_pct numeric(5,1); money numeric(14,2) in AS$; flags boolean not null default false. A child points
-- at its parent with (parent_id, world_id), so a row can never point into another world (#14); flight legs point at
-- their rotation with (rotation_id, airline_id).

-- ---------- §3.2 airports (no world: codes, places and time zones are the game's, the same in every world)
create table public.countries (
  code text primary key,
  name text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.airports (
  code text primary key,
  city text,
  country_code text references public.countries (code),
  lat numeric(8,5),
  lon numeric(8,5),
  utc_offset numeric(4,2),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index airports_country_code_idx on public.airports (country_code);

-- ---------- §3.1 worlds, groups and airlines
create table public.worlds (
  id bigint generated always as identity primary key,
  name text not null,
  game_host text not null,
  kind text not null check (kind in ('exclusive', 'long_term', 'short_term')),
  started_on date,
  ended_on date,
  is_default boolean not null default false,
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint worlds_name_key unique (name),
  constraint worlds_game_host_key unique (game_host)
);
create unique index worlds_one_default on public.worlds (is_default) where is_default;

create table public.world_airports (
  world_id bigint not null references public.worlds (id),
  airport_code text not null references public.airports (code),
  game_airport_id int,
  mct_min smallint,
  night_ban_from time,
  night_ban_to time,
  utc_offset_override numeric(4,2),
  closed boolean not null default false,
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (world_id, airport_code)
);
create index world_airports_airport_code_idx on public.world_airports (airport_code);

create table public.groups (
  id bigint generated always as identity primary key,
  world_id bigint not null references public.worlds (id),
  name text not null,
  kind text not null check (kind in ('ours', 'rival')),
  player_name text,
  owner_user_id uuid references auth.users (id) on delete set null,
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint groups_world_name_key unique (world_id, name),
  constraint groups_id_world_key unique (id, world_id)
);
create index groups_owner_user_id_idx on public.groups (owner_user_id);

create table public.airlines (
  id bigint generated always as identity primary key,
  world_id bigint not null references public.worlds (id),
  group_id bigint,
  game_id int not null,
  game_name text,
  planner_name text,
  public_name text,
  iata_code text,
  country_code text references public.countries (code),
  home_airport_code text references public.airports (code),
  is_lcc boolean not null default false,
  low_demand boolean not null default false,
  active boolean not null default false,
  founded_on date,
  position int,
  livery_color text,
  slug text,
  region_text text,
  role_text text,
  blurb text,
  photo_city text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint airlines_world_game_id_key unique (world_id, game_id),
  constraint airlines_world_planner_name_key unique (world_id, planner_name),
  constraint airlines_id_world_key unique (id, world_id),
  constraint airlines_group_fkey foreign key (group_id, world_id) references public.groups (id, world_id)
);
create index airlines_group_id_idx on public.airlines (group_id);
create index airlines_country_code_idx on public.airlines (country_code);
create index airlines_home_airport_code_idx on public.airlines (home_airport_code);

-- ---------- §3.3 fleet (types first: bases' buy lists and markets point at them)
create table public.aircraft_types (
  id bigint generated always as identity primary key,
  world_id bigint not null references public.worlds (id),
  name text not null,
  family_no int,
  seats_max int,
  cruise_kmh int,
  min_turn_min smallint,
  gap_target_h numeric(4,1),
  maint_per_hour numeric(5,2),
  maint_per_cycle numeric(5,2),
  ground_keep_min smallint,
  price numeric(14,2),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint aircraft_types_world_name_key unique (world_id, name),
  constraint aircraft_types_id_world_key unique (id, world_id)
);

create table public.cabin_configs (
  id bigint generated always as identity primary key,
  world_id bigint not null references public.worlds (id),
  code text not null,
  aircraft_type_id bigint,
  cabin text check (cabin in ('Standard', 'Leisure', 'Leisure Plus', 'Comfort')),
  seats int,
  business_seats int,
  economy_seats int,
  cost numeric(14,2),
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint cabin_configs_world_code_key unique (world_id, code),
  constraint cabin_configs_id_world_key unique (id, world_id),
  constraint cabin_configs_type_fkey foreign key (aircraft_type_id, world_id) references public.aircraft_types (id, world_id)
);
create index cabin_configs_aircraft_type_id_idx on public.cabin_configs (aircraft_type_id);

-- §3.1, continued
create table public.airline_bases (
  id bigint generated always as identity primary key,
  world_id bigint not null references public.worlds (id),
  airline_id bigint not null,
  airport_code text not null references public.airports (code),
  role text not null check (role in ('hub', 'focus')),
  is_main boolean not null default false,
  parent_base_id bigint,
  bank_times time[] check (cardinality(bank_times) <= 4),
  flight_no_from int,
  last_flight_no int,
  hold_note text,
  position int,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint airline_bases_airline_airport_key unique (airline_id, airport_code),
  constraint airline_bases_id_world_key unique (id, world_id),
  constraint airline_bases_airline_fkey foreign key (airline_id, world_id) references public.airlines (id, world_id),
  constraint airline_bases_parent_fkey foreign key (parent_base_id, world_id) references public.airline_bases (id, world_id)
);
create unique index airline_bases_one_main on public.airline_bases (airline_id) where is_main;
create index airline_bases_world_id_idx on public.airline_bases (world_id);
create index airline_bases_airport_code_idx on public.airline_bases (airport_code);
create index airline_bases_parent_base_id_idx on public.airline_bases (parent_base_id);

create table public.airline_aircraft_types (
  world_id bigint not null references public.worlds (id),
  airline_id bigint not null,
  aircraft_type_id bigint not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (airline_id, aircraft_type_id),
  constraint airline_aircraft_types_airline_fkey foreign key (airline_id, world_id) references public.airlines (id, world_id),
  constraint airline_aircraft_types_type_fkey foreign key (aircraft_type_id, world_id) references public.aircraft_types (id, world_id)
);
create index airline_aircraft_types_world_id_idx on public.airline_aircraft_types (world_id);
create index airline_aircraft_types_aircraft_type_id_idx on public.airline_aircraft_types (aircraft_type_id);

create table public.aircraft (
  id bigint generated always as identity primary key,
  world_id bigint not null references public.worlds (id),
  airline_id bigint not null,
  registration text not null,
  aircraft_type_id bigint,
  cabin_config_id bigint,
  base_code text references public.airports (code),
  status text not null check (status in ('on_order', 'delivered', 'active', 'retired')),
  ordered_on date,
  delivery_at timestamptz,
  order_base_code text references public.airports (code),
  order_config_id bigint,
  order_note text,
  checked_on date,
  schedule_changed_on date,
  maintenance_note text,
  retired_on date,
  extra jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint aircraft_world_registration_key unique (world_id, registration),
  constraint aircraft_id_world_key unique (id, world_id),
  constraint aircraft_airline_fkey foreign key (airline_id, world_id) references public.airlines (id, world_id),
  constraint aircraft_type_fkey foreign key (aircraft_type_id, world_id) references public.aircraft_types (id, world_id),
  constraint aircraft_config_fkey foreign key (cabin_config_id, world_id) references public.cabin_configs (id, world_id),
  constraint aircraft_order_config_fkey foreign key (order_config_id, world_id) references public.cabin_configs (id, world_id)
);
create index aircraft_airline_status_idx on public.aircraft (airline_id, status);
create index aircraft_aircraft_type_id_idx on public.aircraft (aircraft_type_id);
create index aircraft_cabin_config_id_idx on public.aircraft (cabin_config_id);
create index aircraft_order_config_id_idx on public.aircraft (order_config_id);
create index aircraft_base_code_idx on public.aircraft (base_code);
create index aircraft_order_base_code_idx on public.aircraft (order_base_code);

create table public.aircraft_cabin_keeps (
  world_id bigint not null references public.worlds (id),
  aircraft_id bigint not null,
  cabin text not null check (cabin in ('Standard', 'Leisure', 'Leisure Plus', 'Comfort')),
  decided_on date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (aircraft_id, cabin),
  constraint aircraft_cabin_keeps_aircraft_fkey foreign key (aircraft_id, world_id) references public.aircraft (id, world_id)
);
create index aircraft_cabin_keeps_world_id_idx on public.aircraft_cabin_keeps (world_id);

-- ---------- §3.4 network
create table public.markets (
  id bigint generated always as identity primary key,
  world_id bigint not null references public.worlds (id),
  airline_id bigint not null,
  name text not null,
  default_type_id bigint,
  default_config_id bigint,
  fare_y_pct numeric(5,1),
  fare_j_pct numeric(5,1),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint markets_airline_name_key unique (airline_id, name),
  constraint markets_id_world_key unique (id, world_id),
  constraint markets_airline_fkey foreign key (airline_id, world_id) references public.airlines (id, world_id),
  constraint markets_type_fkey foreign key (default_type_id, world_id) references public.aircraft_types (id, world_id),
  constraint markets_config_fkey foreign key (default_config_id, world_id) references public.cabin_configs (id, world_id)
);
create index markets_world_id_idx on public.markets (world_id);
create index markets_default_type_id_idx on public.markets (default_type_id);
create index markets_default_config_id_idx on public.markets (default_config_id);

create table public.service_profiles (
  id bigint generated always as identity primary key,
  world_id bigint not null references public.worlds (id),
  airline_id bigint,
  code text not null,
  up_to_km int,
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint service_profiles_world_code_key unique (world_id, code),
  constraint service_profiles_airline_fkey foreign key (airline_id, world_id) references public.airlines (id, world_id)
);
create index service_profiles_airline_id_idx on public.service_profiles (airline_id);

create table public.routes (
  id bigint generated always as identity primary key,
  world_id bigint not null references public.worlds (id),
  airline_id bigint not null,
  hub_code text not null references public.airports (code),
  dest_code text not null references public.airports (code),
  city text,
  country_label text,
  distance_km int,
  market_id bigint,
  stars smallint,
  source text not null check (source in ('research', 'added')),
  removed boolean not null default false,
  removed_note text,
  city_override text,
  distance_override_km int,
  market_override_id bigint,
  stars_override smallint,
  cabin_choice text check (cabin_choice in ('Standard', 'Leisure', 'Leisure Plus', 'Comfort')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- its index also serves the Routes screen's (airline_id, hub_code) lookups, so that index isn't made twice
  constraint routes_airline_hub_dest_key unique (airline_id, hub_code, dest_code),
  constraint routes_id_world_key unique (id, world_id),
  constraint routes_airline_fkey foreign key (airline_id, world_id) references public.airlines (id, world_id),
  constraint routes_market_fkey foreign key (market_id, world_id) references public.markets (id, world_id),
  constraint routes_market_override_fkey foreign key (market_override_id, world_id) references public.markets (id, world_id)
);
create index routes_world_id_idx on public.routes (world_id);
create index routes_hub_code_idx on public.routes (hub_code);
create index routes_dest_code_idx on public.routes (dest_code);
create index routes_market_id_idx on public.routes (market_id);
create index routes_market_override_id_idx on public.routes (market_override_id);

create table public.rotations (
  id bigint generated always as identity primary key,
  world_id bigint not null references public.worlds (id),
  airline_id bigint not null,
  route_id bigint not null,
  legacy_key text,
  service_code text,
  fare_pct numeric(5,1),
  launched_on date,
  note text,
  extra jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint rotations_world_legacy_key_key unique (world_id, legacy_key),
  constraint rotations_id_world_key unique (id, world_id),
  constraint rotations_id_airline_key unique (id, airline_id),
  constraint rotations_airline_fkey foreign key (airline_id, world_id) references public.airlines (id, world_id),
  constraint rotations_route_fkey foreign key (route_id, world_id) references public.routes (id, world_id)
);
create index rotations_airline_id_idx on public.rotations (airline_id);
create index rotations_route_id_idx on public.rotations (route_id);

create table public.flight_legs (
  id bigint generated always as identity primary key,
  world_id bigint not null references public.worlds (id),
  airline_id bigint not null,
  rotation_id bigint not null,
  leg_no smallint not null check (leg_no in (1, 2)),
  flight_no int,
  origin_code text not null references public.airports (code),
  dest_code text not null references public.airports (code),
  aircraft_id bigint,
  days_utc smallint[] not null constraint flight_legs_days_utc_check check (private.is_weekday_set(days_utc)),
  dep_utc_min smallint check (dep_utc_min between 0 and 1439),
  block_min smallint,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint flight_legs_rotation_leg_key unique (rotation_id, leg_no),
  constraint flight_legs_airline_fkey foreign key (airline_id, world_id) references public.airlines (id, world_id),
  constraint flight_legs_rotation_fkey foreign key (rotation_id, airline_id) references public.rotations (id, airline_id) on delete cascade,
  constraint flight_legs_aircraft_fkey foreign key (aircraft_id, world_id) references public.aircraft (id, world_id)
);
create index flight_legs_aircraft_id_idx on public.flight_legs (aircraft_id);
create index flight_legs_world_origin_idx on public.flight_legs (world_id, origin_code);
create index flight_legs_world_dest_idx on public.flight_legs (world_id, dest_code);
create index flight_legs_airline_flight_no_idx on public.flight_legs (airline_id, flight_no);
create index flight_legs_origin_code_idx on public.flight_legs (origin_code);
create index flight_legs_dest_code_idx on public.flight_legs (dest_code);

-- ---------- §3.5 plans
create table public.plan_cards (
  id bigint generated always as identity primary key,
  world_id bigint not null references public.worlds (id),
  airline_id bigint not null,
  aircraft_id bigint not null,
  base_code text references public.airports (code),
  title text,
  note text,
  extra jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint plan_cards_aircraft_key unique (aircraft_id),
  constraint plan_cards_id_world_key unique (id, world_id),
  constraint plan_cards_airline_fkey foreign key (airline_id, world_id) references public.airlines (id, world_id),
  constraint plan_cards_aircraft_fkey foreign key (aircraft_id, world_id) references public.aircraft (id, world_id)
);
create index plan_cards_world_id_idx on public.plan_cards (world_id);
create index plan_cards_airline_id_idx on public.plan_cards (airline_id);
create index plan_cards_base_code_idx on public.plan_cards (base_code);

create table public.plan_card_legs (
  id bigint generated always as identity primary key,
  world_id bigint not null references public.worlds (id),
  plan_card_id bigint not null,
  position int not null,
  flight_no int,
  origin_code text references public.airports (code),
  dest_code text references public.airports (code),
  days_utc smallint[] not null default '{1,2,3,4,5,6,7}' constraint plan_card_legs_days_utc_check check (private.is_weekday_set(days_utc)),
  dep_utc_min smallint check (dep_utc_min between 0 and 1439),
  block_min smallint,
  service_code text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint plan_card_legs_card_position_key unique (plan_card_id, position),
  constraint plan_card_legs_card_fkey foreign key (plan_card_id, world_id) references public.plan_cards (id, world_id) on delete cascade
);
create index plan_card_legs_world_id_idx on public.plan_card_legs (world_id);
create index plan_card_legs_origin_code_idx on public.plan_card_legs (origin_code);
create index plan_card_legs_dest_code_idx on public.plan_card_legs (dest_code);

-- ---------- §3.6 work
create table public.todos (
  id bigint generated always as identity primary key,
  world_id bigint not null references public.worlds (id),
  airline_id bigint,
  legacy_key text,
  title text not null,
  due_on date,
  done boolean not null default false,
  done_at timestamptz,
  note text,
  extra jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint todos_world_legacy_key_key unique (world_id, legacy_key),
  constraint todos_id_world_key unique (id, world_id),
  constraint todos_airline_fkey foreign key (airline_id, world_id) references public.airlines (id, world_id)
);
create index todos_world_done_due_idx on public.todos (world_id, done, due_on);
create index todos_airline_id_idx on public.todos (airline_id);

create table public.todo_items (
  id bigint generated always as identity primary key,
  world_id bigint not null references public.worlds (id),
  todo_id bigint not null,
  position int not null,
  body text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint todo_items_todo_position_key unique (todo_id, position),
  constraint todo_items_todo_fkey foreign key (todo_id, world_id) references public.todos (id, world_id) on delete cascade
);
create index todo_items_world_id_idx on public.todo_items (world_id);

create table public.growth_log (
  id bigint generated always as identity primary key,
  world_id bigint not null references public.worlds (id),
  airline_id bigint not null,
  logged_on date not null,
  move text not null check (move in ('big', 'freq', 'feeder')),
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint growth_log_airline_fkey foreign key (airline_id, world_id) references public.airlines (id, world_id)
);
create index growth_log_world_id_idx on public.growth_log (world_id);
create index growth_log_airline_id_idx on public.growth_log (airline_id);

create table public.spending_log (
  id bigint generated always as identity primary key,
  world_id bigint not null references public.worlds (id),
  airline_id bigint not null,
  spent_on date not null,
  amount numeric(14,2) not null,
  kind text not null check (kind in ('order', 'cabin', 'loss')),
  aircraft_id bigint,
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint spending_log_airline_fkey foreign key (airline_id, world_id) references public.airlines (id, world_id),
  constraint spending_log_aircraft_fkey foreign key (aircraft_id, world_id) references public.aircraft (id, world_id)
);
create index spending_log_world_id_idx on public.spending_log (world_id);
create index spending_log_airline_id_idx on public.spending_log (airline_id);
create index spending_log_aircraft_id_idx on public.spending_log (aircraft_id);

create table public.fare_plan (
  id bigint generated always as identity primary key,
  world_id bigint not null references public.worlds (id),
  airline_id bigint not null,
  route_id bigint,
  legacy_key text,
  cabin_class text check (cabin_class in ('economy', 'business', 'first')),
  change_pct numeric(5,1),
  fare_from numeric(14,2),
  proposed_on date,
  status text not null check (status in ('planned', 'dropped')),
  reason text,
  extra jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint fare_plan_world_legacy_key_key unique (world_id, legacy_key),
  constraint fare_plan_airline_fkey foreign key (airline_id, world_id) references public.airlines (id, world_id),
  constraint fare_plan_route_fkey foreign key (route_id, world_id) references public.routes (id, world_id)
);
create index fare_plan_airline_id_idx on public.fare_plan (airline_id);
create index fare_plan_route_id_idx on public.fare_plan (route_id);

create table public.interline_agreements (
  id bigint generated always as identity primary key,
  world_id bigint not null references public.worlds (id),
  airline_id bigint not null,
  country_code text not null references public.countries (code),
  status text not null check (status in ('to_sign', 'signed', 'declined', 'nopartner')),
  partner text,
  partner_airline_id bigint,
  decided_on date,
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint interline_agreements_airline_country_key unique (airline_id, country_code),
  constraint interline_agreements_airline_fkey foreign key (airline_id, world_id) references public.airlines (id, world_id),
  constraint interline_agreements_partner_fkey foreign key (partner_airline_id, world_id) references public.airlines (id, world_id)
);
create index interline_agreements_world_id_idx on public.interline_agreements (world_id);
create index interline_agreements_country_code_idx on public.interline_agreements (country_code);
create index interline_agreements_partner_airline_id_idx on public.interline_agreements (partner_airline_id);

create table public.monthly_checks (
  id bigint generated always as identity primary key,
  world_id bigint not null references public.worlds (id),
  airline_id bigint,
  task text not null,
  last_done_on date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint monthly_checks_world_airline_task_key unique nulls not distinct (world_id, airline_id, task),
  constraint monthly_checks_airline_fkey foreign key (airline_id, world_id) references public.airlines (id, world_id)
);
create index monthly_checks_airline_id_idx on public.monthly_checks (airline_id);

create table public.dismissals (
  world_id bigint not null references public.worlds (id),
  alert_key text not null,
  dismissed_on date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (world_id, alert_key)
);

create table public.cash_entries (
  world_id bigint not null references public.worlds (id),
  airline_id bigint not null,
  day date not null,
  cash numeric(14,2),
  fixed_next7 numeric(14,2),
  entered_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (airline_id, day),
  constraint cash_entries_airline_fkey foreign key (airline_id, world_id) references public.airlines (id, world_id)
);
create index cash_entries_world_id_idx on public.cash_entries (world_id);

create table public.load_entries (
  world_id bigint not null references public.worlds (id),
  airline_id bigint not null,
  game_date date not null,
  flight_no int not null,
  eco_pct numeric(5,1),
  entered_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (airline_id, game_date, flight_no),
  constraint load_entries_airline_fkey foreign key (airline_id, world_id) references public.airlines (id, world_id)
);
create index load_entries_world_id_idx on public.load_entries (world_id);

create table public.load_days (
  world_id bigint not null references public.worlds (id),
  game_date date not null,
  done boolean not null default false,
  saved_at_ms bigint,
  entered_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (world_id, game_date)
);

-- ---------- §3.7 settings and world rules
create table public.settings (
  id bigint generated always as identity primary key,
  world_id bigint not null references public.worlds (id),
  airline_id bigint,
  key text not null,
  value jsonb not null,
  unit text,
  description text,
  since date,
  reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint settings_world_airline_key_key unique nulls not distinct (world_id, airline_id, key),
  constraint settings_airline_fkey foreign key (airline_id, world_id) references public.airlines (id, world_id)
);
create index settings_airline_id_idx on public.settings (airline_id);

create table public.world_rules (
  id bigint generated always as identity primary key,
  world_id bigint not null references public.worlds (id),
  key text not null,
  value jsonb not null,
  kind text not null check (kind in ('house', 'game', 'permission')),
  unit text,
  description text,
  since date,
  source text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint world_rules_world_key_key unique (world_id, key)
);

-- ---------- §3.10 / §6 the change log (no created_at or updated_at: it is a log)
create table public.change_log (
  id bigint generated always as identity primary key,
  changed_at timestamptz not null default clock_timestamp(),
  world_id bigint,
  table_name text not null,
  row_key jsonb not null,
  op text not null check (op in ('insert', 'update', 'delete')),
  old_values jsonb,
  new_values jsonb,
  actor text not null check (actor in ('planner', 'claude', 'capture', 'script', 'job', 'migration', 'unset')),
  actor_detail text,
  db_role text,
  txid bigint
);
create index change_log_world_changed_idx on public.change_log (world_id, changed_at);
create index change_log_table_changed_idx on public.change_log (table_name, changed_at);

-- §4 and §3.4: legs match their route; changing a route or a rotation can't break that
create trigger check_leg_route before insert or update of rotation_id, leg_no, origin_code, dest_code on public.flight_legs
  for each row execute function private.check_leg_route();
create trigger check_route_legs after update of hub_code, dest_code on public.routes
  for each row execute function private.check_route_legs();
create trigger check_route_legs after update of route_id on public.rotations
  for each row execute function private.check_route_legs();

-- ============================================================ 4. access, timestamps and the change log, table by table
-- Every planner table: RLS with one staff rule per action (the check runs once per query, not per row), anon nothing,
-- authenticated reads and writes (the rules decide who), updated_at kept by trigger, and every change logged.
do $access$
declare t text;
begin
  foreach t in array array[
    'worlds', 'groups', 'airlines', 'airline_bases', 'airline_aircraft_types',
    'countries', 'airports', 'world_airports',
    'aircraft_types', 'cabin_configs', 'aircraft', 'aircraft_cabin_keeps',
    'markets', 'service_profiles', 'routes', 'rotations', 'flight_legs',
    'plan_cards', 'plan_card_legs',
    'todos', 'todo_items', 'growth_log', 'spending_log', 'fare_plan', 'interline_agreements', 'monthly_checks',
    'dismissals', 'cash_entries', 'load_entries', 'load_days',
    'settings', 'world_rules'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('create policy "staff read" on public.%I for select to authenticated using ((select public.is_planner_user()))', t);
    execute format('create policy "staff add" on public.%I for insert to authenticated with check ((select public.is_planner_user()))', t);
    execute format('create policy "staff change" on public.%I for update to authenticated using ((select public.is_planner_user())) with check ((select public.is_planner_user()))', t);
    execute format('create policy "staff remove" on public.%I for delete to authenticated using ((select public.is_planner_user()))', t);
    execute format('revoke all on table public.%I from public, anon, authenticated', t);
    execute format('grant select, insert, update, delete on table public.%I to authenticated', t);
    execute format('create trigger set_updated_at before insert or update on public.%I for each row execute function private.set_updated_at()', t);
    execute format('create trigger log_change after insert or update or delete on public.%I for each row execute function private.log_change()', t);
  end loop;
end
$access$;

-- change_log: staff read it; nobody writes it except private.log_change()
alter table public.change_log enable row level security;
create policy "staff read" on public.change_log for select to authenticated using ((select public.is_planner_user()));
revoke all on table public.change_log from public, anon, authenticated;
grant select on table public.change_log to authenticated;

-- ============================================================ 5. views (§3.12): each shows the caller only what it may read
create view public.flight_legs_local with (security_invoker = true) as
select l.id, l.world_id, l.airline_id, l.rotation_id, l.leg_no, l.flight_no,
       al.iata_code || ' ' || l.flight_no as flight_code,
       l.origin_code, l.dest_code, l.aircraft_id, l.days_utc, l.dep_utc_min, l.block_min,
       x.dep_local_min,
       to_char(make_time(x.dep_local_min / 60, x.dep_local_min % 60, 0), 'HH24:MI') as dep_local,
       x.days_local,
       x.arr_local_min,
       to_char(make_time(x.arr_local_min / 60, x.arr_local_min % 60, 0), 'HH24:MI') as arr_local,
       x.arr_local_day_offset,
       x.arr_utc_min,
       x.arr_utc_day_offset
  from public.flight_legs l
  join public.airlines al on al.id = l.airline_id
  left join public.airports ao on ao.code = l.origin_code
  left join public.world_airports wo on wo.world_id = l.world_id and wo.airport_code = l.origin_code
  left join public.airports ad on ad.code = l.dest_code
  left join public.world_airports wd on wd.world_id = l.world_id and wd.airport_code = l.dest_code
  -- each airport's offset in the leg's world, in minutes (the game has no daylight saving, so this is exact all year)
  cross join lateral (select round(coalesce(wo.utc_offset_override, ao.utc_offset) * 60)::int as dep_off,
                             round(coalesce(wd.utc_offset_override, ad.utc_offset) * 60)::int as arr_off) o
  -- minutes from 00:00 UTC on the departure's UTC day: local departure, UTC arrival, local arrival
  cross join lateral (select l.dep_utc_min + o.dep_off as dep_l, l.dep_utc_min + l.block_min as arr_u,
                             l.dep_utc_min + l.block_min + o.arr_off as arr_l) m
  cross join lateral (select floor(m.dep_l / 1440.0)::int as dep_shift) s
  cross join lateral (
    select ((m.dep_l % 1440) + 1440) % 1440 as dep_local_min,
           case when s.dep_shift is not null then
             (select array_agg(wd order by wd)
                from (select ((((d - 1 + s.dep_shift) % 7) + 7) % 7 + 1)::smallint as wd from unnest(l.days_utc) as d) q)
           end as days_local,
           ((m.arr_l % 1440) + 1440) % 1440 as arr_local_min,
           floor(m.arr_l / 1440.0)::int - s.dep_shift as arr_local_day_offset,
           m.arr_u % 1440 as arr_utc_min,
           floor(m.arr_u / 1440.0)::int as arr_utc_day_offset) x;

create view public.flight_no_clashes with (security_invoker = true) as
select f.world_id, f.airline_id, f.flight_no, f.flight_code, w.weekday,
       count(*)::int as legs,
       array_agg(f.id order by f.id) as leg_ids,
       array_agg(f.aircraft_id order by f.id) as aircraft_ids
  from public.flight_legs_local f
  cross join lateral unnest(coalesce(f.days_local, f.days_utc)) as w(weekday)
 where f.flight_no is not null
 group by f.world_id, f.airline_id, f.flight_no, f.flight_code, w.weekday
having count(*) > 1;

revoke all on table public.flight_legs_local, public.flight_no_clashes from public, anon, authenticated;
grant select on table public.flight_legs_local, public.flight_no_clashes to authenticated;

-- ============================================================ 6. functions: nobody calls them directly
revoke all on function private.is_weekday_set(smallint[]) from public, anon, authenticated;
revoke all on function private.set_updated_at() from public, anon, authenticated;
revoke all on function private.check_leg_route() from public, anon, authenticated;
revoke all on function private.check_route_legs() from public, anon, authenticated;
revoke all on function private.log_change() from public, anon, authenticated;
-- the checks on days_utc call it as whoever writes a leg
grant execute on function private.is_weekday_set(smallint[]) to authenticated;

-- ============================================================ 7. undo one row (§6)
create or replace function private.restore_row(p_table text, p_row_key jsonb, p_as_of timestamptz)
 returns jsonb
 language plpgsql
 set search_path to ''
as $function$
declare
  v_rel regclass;
  v_keys text[];
  v_cols text[];
  v_match text;
  v_cur jsonb;
  v_state jsonb;
  e record;
begin
  -- only tables the change log covers
  if not exists (select 1 from pg_catalog.pg_trigger t join pg_catalog.pg_class c on c.oid = t.tgrelid
                  join pg_catalog.pg_namespace n on n.oid = c.relnamespace
                 where n.nspname = 'public' and c.relname = p_table
                   and t.tgfoid = 'private.log_change()'::pg_catalog.regprocedure) then
    raise exception 'restore_row: % is not a table the change log covers', p_table;
  end if;
  v_rel := pg_catalog.format('public.%I', p_table)::pg_catalog.regclass;
  select array_agg(a.attname::text order by k.ord) into v_keys
    from pg_catalog.pg_index i
    cross join lateral unnest(i.indkey::smallint[]) with ordinality as k(attnum, ord)
    join pg_catalog.pg_attribute a on a.attrelid = i.indrelid and a.attnum = k.attnum
   where i.indrelid = v_rel and i.indisprimary;
  if p_row_key is null or jsonb_typeof(p_row_key) <> 'object'
     or (select count(*) from jsonb_object_keys(p_row_key)) <> cardinality(v_keys)
     or exists (select 1 from unnest(v_keys) as k where not p_row_key ? k) then
    raise exception 'restore_row: the row key must name exactly the primary key of %: %', p_table, v_keys;
  end if;
  select array_agg(a.attname::text order by a.attnum) into v_cols
    from pg_catalog.pg_attribute a
   where a.attrelid = v_rel and a.attnum > 0 and not a.attisdropped and a.attgenerated = '';
  -- (key columns) = (the same columns read from the given key)
  v_match := pg_catalog.format('(%s) = (select %s from jsonb_populate_record(null::%s, $1) k)',
    (select string_agg(pg_catalog.format('t.%I', c), ', ') from unnest(v_keys) as c),
    (select string_agg(pg_catalog.format('k.%I', c), ', ') from unnest(v_keys) as c), v_rel);

  execute pg_catalog.format('select to_jsonb(t) from %s t where %s', v_rel, v_match) into v_cur using p_row_key;
  -- replay the log backwards, newest first, down to the moment asked for
  v_state := v_cur;
  for e in select op, old_values from public.change_log
            where table_name = p_table and row_key = p_row_key and changed_at > p_as_of
            order by changed_at desc, id desc loop
    if e.op = 'insert' then v_state := null;                                       -- it didn't exist before
    elsif e.op = 'delete' then v_state := e.old_values;                            -- it was there, whole
    else v_state := coalesce(v_state, '{}'::jsonb) || coalesce(e.old_values, '{}'::jsonb);   -- undo the changed columns
    end if;
  end loop;

  if v_state is null then
    if v_cur is not null then
      execute pg_catalog.format('delete from %s t where %s', v_rel, v_match) using p_row_key;
    end if;
  elsif v_cur is null then
    execute pg_catalog.format('insert into %s (%s) overriding system value select %s from jsonb_populate_record(null::%s, $1) r',
      v_rel, (select string_agg(pg_catalog.format('%I', c), ', ') from unnest(v_cols) as c),
      (select string_agg(pg_catalog.format('r.%I', c), ', ') from unnest(v_cols) as c), v_rel) using v_state;
  elsif v_state is distinct from v_cur then
    execute pg_catalog.format('update %s t set (%s) = (select %s from jsonb_populate_record(null::%s, $2) r) where %s',
      v_rel, (select string_agg(pg_catalog.format('%I', c), ', ') from unnest(v_cols) as c where c <> all (v_keys)),
      (select string_agg(pg_catalog.format('r.%I', c), ', ') from unnest(v_cols) as c where c <> all (v_keys)),
      v_rel, v_match) using p_row_key, v_state;
  end if;
  return v_state;
end
$function$;
revoke all on function private.restore_row(text, jsonb, timestamptz) from public, anon, authenticated;

-- ============================================================ 8. descriptions (decision #10)
comment on function private.is_weekday_set(smallint[]) is 'True for a set of ISO weekdays as the schedule stores them: 1 (Monday) to 7 (Sunday), sorted, no repeats, at least one. Used by the checks on flight_legs.days_utc and plan_card_legs.days_utc.';
comment on function private.set_updated_at() is 'Trigger on every planner table: sets updated_at when a row is added or really changes, and leaves it as it was when an update changes nothing.';
comment on function private.check_leg_route() is 'Trigger on flight_legs: refuses a leg whose airports don''t match its rotation''s route in its direction (leg 1 from the hub to the destination, leg 2 back).';
comment on function private.check_route_legs() is 'Trigger on routes and rotations: refuses changing a route''s airports, or a rotation''s route, when its flight legs would no longer match.';
comment on function private.log_change() is 'Trigger on every planner table (decision #15): writes one change_log row per row added, changed or removed, naming the writer from equinox.actor and equinox.actor_detail, or planner for a signed-in user and unset otherwise. An update logs only the columns that changed, and nothing when nothing changed. Skipped when equinox.change_log is off, which only postgres can do. Runs as owner, so the log can be written while it stays read-only.';
comment on function private.restore_row(text, jsonb, timestamptz) is 'Puts one row of a logged table back as it was at a moment, by replaying change_log backwards: re-adds a removed row with its own key, undoes changes, or removes a row added since. The restore is logged like any change. For Claude, as postgres: start with the equinox.actor line (design §6).';

comment on table public.worlds is 'One row per AirlineSim world we play in (decision #14). Gander is the only one; is_default marks the world the old planner shows. Every planner table carries its world_id.';
comment on table public.groups is 'A player''s airlines in a world: ours (equinox.) and rival players'' groups. owner_user_id is the sign-in account that owns a group of ours.';
comment on table public.airlines is 'Every airline we track in a world: our own, and from #13''s capture work the rivals the world scan sees (their columns about our airlines stay null). Game ID, codes, home airport, colours and the website''s text, which today are copied in the planner (CODE_AL, CAP_HOME, AIRLINE_ORDER, LIVERY), the website (AL, ORDER) and the capture. The game link is worked out from worlds.game_host and game_id.';
comment on table public.airline_bases is 'Each airline''s hubs and focus cities, with bank times and flight-number blocks. Replaces the planner''s ref.hubs and MAIN_HUB.';
comment on table public.airline_aircraft_types is 'The aircraft types each airline may buy. Replaces the planner''s BUY_TYPES.';
comment on table public.countries is 'Country names by ISO code (-- for unknown). The same in every world. Replaces planner_data.countries.';
comment on table public.airports is 'Every airport in the route research: city, country, position and UTC offset as the game gives them, the same in every world (a world''s own corrections are in world_airports). Replaces planner_data.coords and planner_data.utc. Holds only our six home airports'' codes until the planner''s data moves (#13).';
comment on table public.world_airports is 'What a world says about an airport, only where there is something to say: minimum connection time, night ban, a corrected UTC offset, closure. An airport''s offset in a world is coalesce(utc_offset_override, airports.utc_offset). Replaces site_content.mct, ref.hubs[].mct, ref.curfews and ref.utcOverrides.';
comment on table public.aircraft_types is 'Aircraft types and their figures in a world: seats, cruise speed, turns, maintenance, price. Replaces the planner''s ref.types.';
comment on table public.cabin_configs is 'Cabin layouts (e.g. 321-LEI) with their seats and cost. Replaces the planner''s ref.configs.';
comment on table public.aircraft is 'Each aircraft from order to delivery to service to retirement, one row each. Replaces the planner''s tails and deliveries; status active is what the old planner calls a tail.';
comment on table public.aircraft_cabin_keeps is '"Keep this cabin" decisions: the aircraft keeps its cabin although its routes call for this one, until they call for a different cabin. Replaces the planner''s cabinKeep.';
comment on table public.markets is 'Each airline''s markets with their default aircraft, cabin and fares. Replaces the planner''s ref.markets.';
comment on table public.service_profiles is 'On-board service by distance (S1, S2, …). airline_id null means every airline without its own. Replaces the planner''s ref.services.';
comment on table public.routes is 'Every route an airline could fly, has added or has removed: the route research and the routes added in the planner, with the planner''s overrides (null = the research value; research refreshes never touch them). Replaces planner_data.routes, routesAdded, routeEdits and routeCabin.';
comment on table public.rotations is 'An aircraft''s out-and-back pair on a route: what the old planner calls a frequency. Its flights are in flight_legs. Replaces the planner''s freqs.';
comment on table public.flight_legs is 'One row per flight in the schedule, in UTC (design §4): departure minute, UTC weekdays and block time. Leg 1 leaves the hub, leg 2 returns, and the airports must match the route that way. A flight number can repeat on other days, so flight_no_clashes lists real clashes. Local times are in flight_legs_local.';
comment on table public.plan_cards is 'A plan for one aircraft''s flying, on order or flying, kept after it is filed as the record of what was planned (whether it is filed is worked out, not stored). Replaces the planner''s plans.';
comment on table public.plan_card_legs is 'A plan card''s flights, with the same time rules as flight_legs (UTC). Replaces plans[].legs.';
comment on table public.todos is 'The planner''s To-do board. created_at is the item''s own creation time. Replaces the planner''s todos.';
comment on table public.todo_items is 'A to-do''s steps, in order. Replaces todos[].items.';
comment on table public.growth_log is 'Moves logged under the order rotation: big, freq or feeder. Replaces the planner''s growthLog.';
comment on table public.spending_log is 'Money spent, in AS$: aircraft orders, cabins and refits, losses. Replaces the planner''s capex.';
comment on table public.fare_plan is 'Fare tests to make in the game, and whether each is still planned or was dropped. Replaces the planner''s farePlan.';
comment on table public.interline_agreements is 'Interline status per airline and country: to sign, signed, declined, or no partner there. Replaces the planner''s interline.';
comment on table public.monthly_checks is 'When each monthly check was last done, per airline or for the group as a whole (airline_id null). Replaces the planner''s monthly.';
comment on table public.dismissals is 'Alerts dismissed on the planner''s Home, by the old planner''s key (e.g. maint|B-0162). Replaces the planner''s dismissed.';
comment on table public.cash_entries is 'Cash and the next 7 days'' fixed costs, in AS$, typed by hand or kept from before the capture: only figures the capture doesn''t give. Replaces the hand-typed part of the planner''s cash and fixed7.';
comment on table public.load_entries is 'Economy loads typed by hand, per flight and game date. Replaces the typed part of planner_loads.';
comment on table public.load_days is 'A load day''s flags typed in the planner (whether the day is complete). Replaces the day flags in planner_loads.';
comment on table public.settings is 'Our own planning choices as data (decision #14): the manual''s rule numbers, thresholds and display choices for a world, with per-airline overrides. The old planner keeps its own copies in its code until #18.';
comment on table public.world_rules is 'The world''s own rules as data (decision #14): house rules, game settings, and whether #12''s items (interlines between our airlines, the capture''s salary step, the world scanner, the schedule check) are allowed there.';
comment on table public.change_log is 'Every change to the planner''s tables (decision #15): which row, added, changed or removed, the old and new values (for a change, only the columns that changed), when, and who. Written only by private.log_change(); staff can read it, nobody can edit it. Kept 12 months, then archived.';

comment on view public.flight_legs_local is 'Each flight leg with its flight code (KF 1001) and its times as the game shows them: local departure and arrival and local weekdays, plus the arrival in UTC and its day offset. Worked out from the UTC schedule with each airport''s offset in the leg''s world; null where an offset or the block time is missing. Shows the caller only what it may read.';
comment on view public.flight_no_clashes is 'An airline''s flight number used by two or more legs departing on the same weekday (local at the origin, as the planner''s check counts it). Numbers may repeat on other days, so only real clashes are listed. Shows the caller only what it may read.';

comment on column public.worlds.game_host is 'The world''s address, e.g. gander.airlinesim.aero';
comment on column public.worlds.kind is 'exclusive, long_term or short_term';
comment on column public.worlds.is_default is 'The world the old planner shows; at most one';
comment on column public.groups.kind is 'ours or rival';
comment on column public.groups.player_name is 'The player''s name in the game';
comment on column public.groups.owner_user_id is 'The sign-in account that owns this group (ours only)';
comment on column public.airlines.group_id is 'Null for a rival not yet placed in a group';
comment on column public.airlines.game_id is 'The game''s enterprise ID, e.g. 114';
comment on column public.airlines.game_name is 'The name as the game shows it';
comment on column public.airlines.planner_name is 'The old planner''s key, e.g. Pan American';
comment on column public.airlines.public_name is 'The name on the website, e.g. Pan Am';
comment on column public.airlines.iata_code is 'The airline code in flight numbers, e.g. AW';
comment on column public.airlines.home_airport_code is 'Where the game''s events page shows the airline''s times';
comment on column public.airlines.is_lcc is 'A low-cost carrier, for the house rules';
comment on column public.airlines.low_demand is 'Held as a low-demand-country holding, for the house rules';
comment on column public.airlines.position is 'Display order, 1 first';
comment on column public.airlines.livery_color is 'Brand colour, #RRGGBB';
comment on column public.airlines.slug is 'The website''s address part, e.g. pan-am';
comment on column public.airlines.region_text is 'Website text: where it flies';
comment on column public.airlines.role_text is 'Website text: its role in the group';
comment on column public.airlines.blurb is 'Website text: the description on Our airlines';
comment on column public.airlines.photo_city is 'Website: the city whose photo stands for the airline';
comment on column public.airline_bases.role is 'hub or focus';
comment on column public.airline_bases.is_main is 'The airline''s main hub; one per airline';
comment on column public.airline_bases.parent_base_id is 'A focus city''s hub';
comment on column public.airline_bases.bank_times is 'Bank times, local clock time; 4 slots, null = empty';
comment on column public.airline_bases.flight_no_from is 'First flight number of the base''s block, e.g. 1000';
comment on column public.airline_bases.hold_note is 'Why the base is on hold, if it is';
comment on column public.airports.utc_offset is 'Hours from UTC, e.g. 5.50, 5.75, -5.00; the game runs standard time all year';
comment on column public.world_airports.game_airport_id is 'The game''s own airport ID';
comment on column public.world_airports.mct_min is 'Minimum connection time, minutes';
comment on column public.world_airports.night_ban_from is 'Night ban start, local clock time';
comment on column public.world_airports.night_ban_to is 'Night ban end, local clock time';
comment on column public.world_airports.utc_offset_override is 'A correction to airports.utc_offset for this world, in hours';
comment on column public.world_airports.closed is 'The airport is closed in this world (e.g. PNH)';
comment on column public.aircraft_types.family_no is 'The game''s aircraft family number';
comment on column public.aircraft_types.min_turn_min is 'Shortest turn, minutes';
comment on column public.aircraft_types.gap_target_h is 'Target maintenance gap, hours';
comment on column public.aircraft_types.maint_per_hour is 'Maintenance need per flight hour';
comment on column public.aircraft_types.maint_per_cycle is 'Maintenance need per take-off and landing';
comment on column public.aircraft_types.ground_keep_min is 'The turn the game keeps at each end, minutes (the planner''s greens)';
comment on column public.aircraft_types.price is 'AS$';
comment on column public.cabin_configs.code is 'e.g. 321-LEI';
comment on column public.cabin_configs.cabin is 'Standard, Leisure, Leisure Plus or Comfort';
comment on column public.cabin_configs.cost is 'AS$';
comment on column public.aircraft.registration is 'e.g. N001AW; a field, not the key, so a re-registration touches one row';
comment on column public.aircraft.aircraft_type_id is 'Today''s type';
comment on column public.aircraft.cabin_config_id is 'Today''s cabin';
comment on column public.aircraft.base_code is 'Today''s base';
comment on column public.aircraft.status is 'on_order, delivered (arrived, not yet filed into the planner), active (the old planner''s tail) or retired';
comment on column public.aircraft.delivery_at is 'Arrival in the game (the planner''s deliveries[].utc)';
comment on column public.aircraft.order_base_code is 'Base as ordered';
comment on column public.aircraft.order_config_id is 'Cabin as ordered; can differ from today''s after a refit';
comment on column public.aircraft.checked_on is 'The one-week check, Gitesh''s to mark (manual §1)';
comment on column public.aircraft.schedule_changed_on is 'When its schedule last changed, which restarts the one-week check';
comment on column public.aircraft.maintenance_note is 'The planner''s maint';
comment on column public.aircraft.extra is 'For the adapter only: any field the old planner adds that the table doesn''t know, so nothing is dropped. Expected empty';
comment on column public.aircraft_cabin_keeps.cabin is 'The cabin its routes call for, which it keeps not having';
comment on column public.markets.name is 'e.g. Transatlantic – dense';
comment on column public.markets.fare_y_pct is 'Economy fare, percent of the game''s standard';
comment on column public.markets.fare_j_pct is 'Business fare, percent of the game''s standard';
comment on column public.service_profiles.code is 'S1, S2, …; unique in a world';
comment on column public.service_profiles.up_to_km is 'Used for routes up to this distance';
comment on column public.routes.hub_code is 'Where the route starts: the airline''s hub or focus city';
comment on column public.routes.city is 'A label, e.g. Shanghai (Pudong)';
comment on column public.routes.country_label is 'The country as the research gave it: a name or a code';
comment on column public.routes.stars is 'The research''s rating';
comment on column public.routes.source is 'research or added (in the planner)';
comment on column public.routes.removed is 'Taken off the airline''s list';
comment on column public.routes.city_override is 'Typed in the planner; null = the research value';
comment on column public.routes.distance_override_km is 'Typed in the planner; null = the research value';
comment on column public.routes.market_override_id is 'Typed in the planner; null = the research value';
comment on column public.routes.stars_override is 'Typed in the planner; null = the research value';
comment on column public.routes.cabin_choice is 'The cabin chosen for the route (the planner''s routeCabin)';
comment on column public.rotations.legacy_key is 'The old planner''s frequency id, e.g. z5qbaeg, kept for the adapter until #18';
comment on column public.rotations.service_code is 'On-board service, e.g. S3';
comment on column public.rotations.fare_pct is 'Fare, percent of standard (100; Ryanair 85)';
comment on column public.rotations.extra is 'For the adapter only: fields the table doesn''t know. Expected empty';
comment on column public.flight_legs.leg_no is '1 = out from the hub, 2 = back';
comment on column public.flight_legs.flight_no is 'e.g. 1001, shown with the airline''s code as KF 1001';
comment on column public.flight_legs.aircraft_id is 'Null only while being typed';
comment on column public.flight_legs.days_utc is 'UTC weekdays it departs, ISO (1 = Monday): sorted, no repeats, at least one';
comment on column public.flight_legs.dep_utc_min is 'Departure, minutes after 00:00 UTC (0 to 1439); null only while being typed';
comment on column public.flight_legs.block_min is 'Block time, minutes, from the game''s times; null = arrival not typed (the planner estimates it)';
comment on column public.flight_legs_local.flight_code is 'e.g. KF 1001';
comment on column public.flight_legs_local.dep_local_min is 'Departure, minutes after local midnight at the origin';
comment on column public.flight_legs_local.dep_local is 'Departure, local clock time at the origin, as the game shows it';
comment on column public.flight_legs_local.days_local is 'Local weekdays it departs at the origin, ISO (1 = Monday)';
comment on column public.flight_legs_local.arr_local_min is 'Arrival, minutes after local midnight at the destination';
comment on column public.flight_legs_local.arr_local is 'Arrival, local clock time at the destination';
comment on column public.flight_legs_local.arr_local_day_offset is 'Local arrival day minus local departure day: 0 = the same day, 1 = the next';
comment on column public.flight_legs_local.arr_utc_min is 'Arrival, minutes after 00:00 UTC';
comment on column public.flight_legs_local.arr_utc_day_offset is 'UTC arrival day minus UTC departure day';
comment on column public.flight_no_clashes.weekday is 'Departure weekday, local at the origin, ISO (1 = Monday); UTC where the origin''s offset isn''t known';
comment on column public.flight_no_clashes.legs is 'How many legs use the number that day';
comment on column public.plan_cards.aircraft_id is 'The aircraft the card plans, on order or flying';
comment on column public.plan_cards.title is 'e.g. HYD + CKG';
comment on column public.plan_cards.extra is 'For the adapter only: fields the table doesn''t know. Expected empty';
comment on column public.plan_card_legs.position is 'Order on the card';
comment on column public.plan_card_legs.days_utc is 'UTC weekdays it departs, ISO; every day unless set';
comment on column public.plan_card_legs.dep_utc_min is 'Departure, minutes after 00:00 UTC';
comment on column public.plan_card_legs.block_min is 'Block time, minutes';
comment on column public.todos.legacy_key is 'The old planner''s to-do id, kept for the adapter until #18';
comment on column public.todos.created_at is 'When the to-do was made (its own time, not the row''s)';
comment on column public.todos.extra is 'For the adapter only: fields the table doesn''t know. Expected empty';
comment on column public.todo_items.position is 'Order in the to-do';
comment on column public.growth_log.move is 'big, freq or feeder';
comment on column public.spending_log.amount is 'AS$';
comment on column public.spending_log.kind is 'order, cabin or loss';
comment on column public.fare_plan.legacy_key is 'The old planner''s fare-plan id, kept for the adapter until #18';
comment on column public.fare_plan.cabin_class is 'economy, business or first';
comment on column public.fare_plan.change_pct is 'The fare change to make, percent';
comment on column public.fare_plan.fare_from is 'The fare before the change, AS$';
comment on column public.fare_plan.status is 'planned or dropped';
comment on column public.fare_plan.extra is 'For the adapter only: fields the table doesn''t know. Expected empty';
comment on column public.interline_agreements.status is 'to_sign, signed, declined or nopartner';
comment on column public.interline_agreements.partner is 'The partner as the game names it, e.g. Emirates (41)';
comment on column public.interline_agreements.partner_airline_id is 'The partner, once it is in airlines';
comment on column public.monthly_checks.airline_id is 'Null = the group as a whole';
comment on column public.monthly_checks.task is 'e.g. salaries';
comment on column public.dismissals.alert_key is 'The old planner''s key, e.g. maint|B-0162';
comment on column public.cash_entries.day is 'The planner''s date key';
comment on column public.cash_entries.cash is 'AS$';
comment on column public.cash_entries.fixed_next7 is 'Fixed costs in the next 7 days, AS$';
comment on column public.load_entries.game_date is 'The local date at departure, as the game''s loads page shows it';
comment on column public.load_entries.eco_pct is 'Economy load, percent; null = cleared';
comment on column public.load_days.done is 'The day is complete';
comment on column public.load_days.saved_at_ms is 'When the planner saved it, milliseconds since 1970 (UTC)';
comment on column public.settings.airline_id is 'Null = the whole world; set = that airline''s override';
comment on column public.settings.since is 'When the rule started';
comment on column public.world_rules.kind is 'house, game or permission';
comment on column public.world_rules.since is 'When the rule started';
comment on column public.world_rules.source is 'Where the rule comes from';
comment on column public.change_log.changed_at is 'When, to the microsecond (clock_timestamp())';
comment on column public.change_log.world_id is 'The changed row''s world; null for countries and airports';
comment on column public.change_log.row_key is 'The changed row''s primary key, e.g. {"id": 812}';
comment on column public.change_log.op is 'insert, update or delete';
comment on column public.change_log.old_values is 'Before: the whole row for a delete, only the changed columns for an update';
comment on column public.change_log.new_values is 'After: the whole row for an insert, only the changed columns for an update';
comment on column public.change_log.actor is 'Who: planner, claude, capture, script, job, migration, or unset when the writer didn''t say';
comment on column public.change_log.actor_detail is 'Which one: a tab ID, a script or chat name';
comment on column public.change_log.db_role is 'The database role the change was made as';
comment on column public.change_log.txid is 'The transaction, so one save''s changes can be grouped';

-- ============================================================ 9. reference rows (§9 step 1)
-- From capture/capture_all.user.js (game IDs), the planner's constants (CODE_AL codes, CAP_HOME home airports,
-- AIRLINE_ORDER display order, LIVERY colours, LCC) and web/assets/site.js (public names, slugs and the website's text).
-- Left null where none of them says: the world's start date, the group's player name, each airline's game name, country
-- and founding date. The owner is found by the staff email, never written here; it is null where there are no sign-in
-- accounts (the rehearsal's copy). Loaded like the rest of #13's data: as migration, with logging off (§9).
do $reference$
declare v_world bigint; v_group bigint; v_owner uuid;
begin
  perform set_config('equinox.actor', 'migration', true),
          set_config('equinox.actor_detail', '20261009210000_planner_tables', true),
          set_config('equinox.change_log', 'off', true);

  insert into public.worlds (name, game_host, kind, is_default)
  values ('Gander', 'gander.airlinesim.aero', 'exclusive', true)
  returning id into v_world;

  select u.id into v_owner
    from auth.users u join public.planner_users p on lower(p.email) = lower(u.email)
   order by u.created_at limit 1;
  insert into public.groups (world_id, name, kind, owner_user_id)
  values (v_world, 'equinox.', 'ours', v_owner)
  returning id into v_group;

  -- the home airports' codes only; the planner's data fills in the rest (#13)
  insert into public.airports (code) values ('JFK'), ('DEL'), ('CDG'), ('LGW'), ('PVG'), ('KUL');

  insert into public.airlines (world_id, group_id, game_id, planner_name, public_name, iata_code, home_airport_code,
                               is_lcc, active, position, livery_color, slug, region_text, role_text, blurb, photo_city)
  values
    (v_world, v_group, 114, 'Pan American', 'Pan Am', 'AW', 'JFK', false, true, 1, '#2A8FD8', 'pan-am',
     'North America and across the Atlantic', 'Transatlantic and the Americas',
     'Pan Am is the group''s airline for North America and the Atlantic. From New York JFK it connects the United States with Europe, Mexico and the Caribbean, and feeds the rest of the group through London and Paris.',
     'New York'),
    (v_world, v_group, 113, 'Kingfisher', 'Kingfisher', 'KF', 'DEL', false, true, 2, '#D7263D', 'kingfisher',
     'India and South Asia', 'India, South Asia and the long-haul links from Delhi',
     'Kingfisher connects India from its Delhi hub, flying to cities across the country and long-haul from Delhi to London, Paris, Amsterdam and New York.',
     'Delhi'),
    (v_world, v_group, 112, 'Ryanair', 'Ryanair', 'FR', 'CDG', true, true, 3, '#F1C21B', 'ryanair',
     'Europe', 'Europe, point to point',
     'Ryanair flies Europe point to point from Paris CDG and Amsterdam, with simple fares, two aircraft types and quick turnarounds.',
     'Paris'),
    (v_world, v_group, 203, 'Virgin Atlantic', 'Virgin Atlantic', 'VS', 'LGW', false, true, 4, '#8E1537', 'virgin-atlantic',
     'the United Kingdom and Europe', 'London and Europe',
     'Virgin Atlantic flies the group''s London network from Gatwick, with Manchester and Edinburgh as further bases, linking Britain with more than thirty European cities and with Pan Am across the Atlantic.',
     'London'),
    (v_world, v_group, 208, 'China Eastern', 'China Eastern', 'MU', 'PVG', false, true, 5, '#1C3F8C', 'china-eastern',
     'China and North-East Asia', 'China and North-East Asia',
     'China Eastern flies across China from Shanghai Pudong, with bases at Xi''an, Kunming and Beijing Daxing. It links China with Japan, Korea, Taiwan, Hong Kong and South-East Asia.',
     'Shanghai'),
    (v_world, v_group, 210, 'Malaysia Airlines', 'Malaysia Airlines', 'MH', 'KUL', false, true, 6, '#0F8C8C', 'malaysia-airlines',
     'South-East Asia', 'South-East Asia and the KUL connecting hub',
     'Malaysia Airlines connects China, India and South-East Asia through its Kuala Lumpur hub, linking around forty cities.',
     'Kuala Lumpur');

  perform set_config('equinox.change_log', '', true), set_config('equinox.actor', '', true), set_config('equinox.actor_detail', '', true);
end
$reference$;

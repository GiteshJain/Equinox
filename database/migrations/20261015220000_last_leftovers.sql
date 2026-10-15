-- The last leftovers from the planner rebuild (spec docs/specs/2026-10-15-last-leftovers.md, design §16): the cabin an
-- order comes with, and the airports' website names and city photos, made data.
--
-- Adds one column, one table and one site_content row, fills them, and replaces two functions with the same arguments.
-- Takes nothing away from anyone and moves no answer, so it can be applied from the chat:
--   aircraft_types.order_config_id: the cabin layout an order of the type comes with, for every airline without its own.
--   airline_order_cabins (new planner table: staff read and write, logged, as the other 32): an airline's own order cabin
--     for a type, where it differs from the type's (Ryanair's Standard layouts, as a low-cost airline). An empty layout
--     means none for that airline.
--     Both are filled from exactly what private.fig_order_cabin() gave before this change for every airline and every
--     type of its world (the old planner's DEFAULT_CABIN rule): the type's is the layout most of the world's airlines
--     got (a tie: the newer layout), and an airline that got another has its own row. The fill is logged as migration.
--   private.fig_order_cabin(p_airline_id, p_type_id): reads them: the airline's own row for the type, else the type's
--     order cabin; null for an airline or type that isn't there, as before. order_cabin(), cash_forecast() and the
--     briefing's figures read it as before. Before the change is committed the migration checks that it gives what it
--     gave for every pair, and stops if any moved.
--   public.planner_save(p_changes, p_client): exactly as 20261013200000_home.sql left it, with airline_order_cabins on
--     its list of tables (33), so Reference saves an airline's own order cabin as one action.
--   site_content airport_cities: which city's photo an airport takes on the website (photo) and the name the website
--     gives it (name), the lists the website (web/assets/site.js, CITYPHOTO and NAMES) and the planner's Photos screen
--     (CITY_PHOTO and NAMES) each kept in their code, word for word the same. site_public() carries every site_content
--     key (content.airport_cities) without a change, and both now read it from there. site_admin() content can change it.
-- Order after "merge": apply this first, then merge, so the website never runs without its lists (the website and planner
-- live today ignore the new row, column and table).

select set_config('equinox.actor', 'migration', true),
       set_config('equinox.actor_detail', '20261015220000_last_leftovers', true);

-- ============================================================ 1. the order cabin, as data
-- what the rule gives today, for every airline and every type of its world, before anything changes
create temporary table t_order_was on commit drop as
select t.world_id, a.id as airline_id, t.id as aircraft_type_id, private.fig_order_cabin(a.id, t.id) as config_id
  from public.airlines a
  join public.aircraft_types t on t.world_id = a.world_id;

alter table public.aircraft_types add column if not exists order_config_id bigint;
alter table public.aircraft_types add constraint aircraft_types_order_config_fkey
  foreign key (order_config_id, world_id) references public.cabin_configs (id, world_id);
create index if not exists aircraft_types_order_config_id_idx on public.aircraft_types (order_config_id);

create table public.airline_order_cabins (
  world_id bigint not null references public.worlds (id),
  airline_id bigint not null,
  aircraft_type_id bigint not null,
  order_config_id bigint,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (airline_id, aircraft_type_id),
  constraint airline_order_cabins_airline_fkey foreign key (airline_id, world_id) references public.airlines (id, world_id),
  constraint airline_order_cabins_type_fkey foreign key (aircraft_type_id, world_id) references public.aircraft_types (id, world_id),
  constraint airline_order_cabins_config_fkey foreign key (order_config_id, world_id) references public.cabin_configs (id, world_id)
);
create index airline_order_cabins_world_id_idx on public.airline_order_cabins (world_id);
create index airline_order_cabins_aircraft_type_id_idx on public.airline_order_cabins (aircraft_type_id);
create index airline_order_cabins_order_config_id_idx on public.airline_order_cabins (order_config_id);

-- as every planner table (20261009210000_planner_tables.sql): RLS with one staff rule per action (the check once per
-- query), nothing for anon, authenticated reads and writes (the rules decide who), updated_at by trigger, every change logged
alter table public.airline_order_cabins enable row level security;
create policy "staff read" on public.airline_order_cabins for select to authenticated using ((select public.is_planner_user()));
create policy "staff add" on public.airline_order_cabins for insert to authenticated with check ((select public.is_planner_user()));
create policy "staff change" on public.airline_order_cabins for update to authenticated using ((select public.is_planner_user())) with check ((select public.is_planner_user()));
create policy "staff remove" on public.airline_order_cabins for delete to authenticated using ((select public.is_planner_user()));
revoke all on table public.airline_order_cabins from public, anon, authenticated;
grant select, insert, update, delete on table public.airline_order_cabins to authenticated;
create trigger set_updated_at before insert or update on public.airline_order_cabins for each row execute function private.set_updated_at();
create trigger log_change after insert or update or delete on public.airline_order_cabins for each row execute function private.log_change();

-- the type's order cabin: the layout most of its world's airlines get (a tie: the newer layout)
update public.aircraft_types t set order_config_id = m.config_id
  from (select distinct on (w.aircraft_type_id) w.aircraft_type_id, w.config_id
          from t_order_was w
         group by w.aircraft_type_id, w.config_id
         order by w.aircraft_type_id, count(*) desc, w.config_id desc nulls last) m
 where m.aircraft_type_id = t.id and t.order_config_id is distinct from m.config_id;

-- an airline's own, where it gets another
insert into public.airline_order_cabins (world_id, airline_id, aircraft_type_id, order_config_id)
select w.world_id, w.airline_id, w.aircraft_type_id, w.config_id
  from t_order_was w
  join public.aircraft_types t on t.id = w.aircraft_type_id
 where w.config_id is distinct from t.order_config_id;

create or replace function private.fig_order_cabin(p_airline_id bigint, p_type_id bigint)
 returns bigint
 language sql
 stable
 set search_path to ''
as $function$
  select case when x.airline_id is not null then x.order_config_id else t.order_config_id end
    from public.airlines a
    join public.aircraft_types t on t.id = p_type_id
    left join public.airline_order_cabins x on x.airline_id = a.id and x.aircraft_type_id = t.id
   where a.id = p_airline_id
$function$;

-- nothing moves: the data gives what the rule gave for every pair, or the migration stops here
do $check$
declare n_pairs int; n_moved int; n_types int; n_with int; n_own int; n_airlines int;
begin
  select count(*), count(*) filter (where private.fig_order_cabin(w.airline_id, w.aircraft_type_id) is distinct from w.config_id)
    into n_pairs, n_moved from t_order_was w;
  if n_moved > 0 then
    raise exception 'the order cabin as data moves % of % airline-and-type pairs; nothing was applied', n_moved, n_pairs;
  end if;
  select count(*), count(t.order_config_id) into n_types, n_with from public.aircraft_types t;
  select count(*), count(distinct x.airline_id) into n_own, n_airlines from public.airline_order_cabins x;
  raise notice 'order cabins as data: % types (% with a layout); % rows of an airline''s own, for % airline(s); the same answer for all % airline-and-type pairs',
    n_types, n_with, n_own, n_airlines, n_pairs;
end
$check$;

-- ============================================================ 2. planner_save(): airline_order_cabins on its list
-- As 20261013200000_home.sql left it, with the 33rd planner table.
create or replace function public.planner_save(p_changes jsonb, p_client text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  -- the 33 planner tables, each with the change-log trigger (migration 20261009210000_planner_tables.sql, §4; the 33rd,
  -- airline_order_cabins, 20261015220000_last_leftovers.sql)
  v_tables constant text[] := array[
    'worlds', 'groups', 'airlines', 'airline_bases', 'airline_aircraft_types',
    'countries', 'airports', 'world_airports',
    'aircraft_types', 'cabin_configs', 'aircraft', 'aircraft_cabin_keeps',
    'markets', 'service_profiles', 'routes', 'rotations', 'flight_legs',
    'plan_cards', 'plan_card_legs',
    'todos', 'todo_items', 'growth_log', 'spending_log', 'fare_plan', 'interline_agreements', 'monthly_checks',
    'dismissals', 'cash_entries', 'load_entries', 'load_days',
    'settings', 'world_rules', 'airline_order_cabins'];
  v_actor text := current_setting('equinox.actor', true);
  v_detail text := current_setting('equinox.actor_detail', true);
  w bigint;
  c jsonb;
  i bigint;
  v_list jsonb := '[]'::jsonb;
  v_table text;
  v_op text;
  v_key jsonb;
  v_vals jsonb;
  v_pk text[];
  v_cols text[];
  v_bad text;
  v_base timestamptz;
  v_where text;
  v_names text;
  v_from text;
  v_row jsonb;
  v_at timestamptz;
  v_clashes jsonb := '[]'::jsonb;
  v_rows jsonb := '[]'::jsonb;
  -- "as" and "from": the names given to inserts so far (name -> its primary key column), and, while writing, the key
  -- each named insert made (name -> value)
  v_as text;
  v_take jsonb;
  v_named jsonb := '{}'::jsonb;
  v_made jsonb := '{}'::jsonb;
  f record;
begin
  if not private.caller_is_staff() then raise exception 'only planner staff can save the planner' using errcode = '42501'; end if;
  if jsonb_typeof(p_changes) is distinct from 'array' then
    raise exception 'planner_save: the changes must be a JSON list' using errcode = '22023';
  end if;

  -- 1. every change is checked before any row is read or written
  for c, i in select e.value, e.ordinality from jsonb_array_elements(p_changes) with ordinality as e loop
    if jsonb_typeof(c) is distinct from 'object' then
      raise exception 'planner_save: change % isn''t an object', i using errcode = '22023';
    end if;
    v_table := c ->> 'table';
    v_op := c ->> 'op';
    if v_table is null or not (v_table = any (v_tables)) then
      raise exception 'planner_save: change %: % isn''t one of the planner''s tables (only the 33 the change log covers)',
        i, coalesce(v_table, 'no table') using errcode = '22023';
    end if;
    if v_op is null or v_op not in ('insert', 'update', 'delete') then
      raise exception 'planner_save: change %: op must be insert, update or delete, not %', i, coalesce(v_op, 'nothing')
        using errcode = '22023';
    end if;
    v_key := c -> 'key';
    v_vals := c -> 'values';
    v_take := c -> 'from';
    if v_key = 'null'::jsonb then v_key := null; end if;
    if v_vals = 'null'::jsonb then v_vals := null; end if;
    if v_take = 'null'::jsonb then v_take := null; end if;
    if v_key is not null and jsonb_typeof(v_key) <> 'object' then
      raise exception 'planner_save: change %: key must be an object, e.g. {"id": 812}', i using errcode = '22023';
    end if;
    if v_vals is not null and jsonb_typeof(v_vals) <> 'object' then
      raise exception 'planner_save: change %: values must be an object of columns', i using errcode = '22023';
    end if;
    select array_agg(a.attname::text order by k.n) into v_pk
      from pg_catalog.pg_index x
      cross join lateral unnest(x.indkey::smallint[]) with ordinality as k(attnum, n)
      join pg_catalog.pg_attribute a on a.attrelid = x.indrelid and a.attnum = k.attnum
     where x.indrelid = format('public.%I', v_table)::regclass and x.indisprimary;
    select array_agg(a.attname::text) into v_cols
      from pg_catalog.pg_attribute a
     where a.attrelid = format('public.%I', v_table)::regclass and a.attnum > 0 and not a.attisdropped;

    -- "from": columns whose value is the key of a row an earlier insert in this call makes (it names that row with "as")
    if v_take is not null then
      if jsonb_typeof(v_take) <> 'object' or v_take = '{}'::jsonb then
        raise exception 'planner_save: change %: from must be an object of columns, e.g. {"todo_id": "new-todo"}', i using errcode = '22023';
      end if;
      if v_op = 'delete' then
        raise exception 'planner_save: change %: a delete takes no from', i using errcode = '22023';
      end if;
      for f in select e.key, e.value from jsonb_each(v_take) as e loop
        if jsonb_typeof(f.value) <> 'string' or not (v_named ? (f.value #>> '{}')) then
          raise exception 'planner_save: change %: from names %, which no earlier insert in this call is called (as)', i, f.value
            using errcode = '22023';
        end if;
        if not (f.key = any (v_cols)) then
          raise exception 'planner_save: change %: % has no column %', i, v_table, f.key using errcode = '22023';
        end if;
        if f.key = 'updated_at' or coalesce(v_vals, '{}'::jsonb) ? f.key then
          raise exception 'planner_save: change %: % is given both in values and in from', i, f.key using errcode = '22023';
        end if;
      end loop;
    end if;

    if v_op in ('update', 'delete') then
      if v_key is null
         or (select array_agg(k order by k) from jsonb_object_keys(v_key) as k) is distinct from
            (select array_agg(p order by p) from unnest(v_pk) as p) then
        raise exception 'planner_save: change %: the key must name exactly the primary key of % (%)',
          i, v_table, array_to_string(v_pk, ', ') using errcode = '22023';
      end if;
      if exists (select 1 from jsonb_each(v_key) as e where e.value = 'null'::jsonb) then
        raise exception 'planner_save: change %: a key value is empty', i using errcode = '22023';
      end if;
      if c ->> 'base' is null then
        raise exception 'planner_save: change %: an % needs base, the row''s updated_at as it was loaded', i, v_op
          using errcode = '22023';
      end if;
      begin
        v_base := (c ->> 'base')::timestamptz;
      exception when others then
        raise exception 'planner_save: change %: base isn''t a time: %', i, c ->> 'base' using errcode = '22023';
      end;
    end if;
    if v_op = 'insert' then
      -- a key given with an insert (a table keyed by its own columns, like dismissals) is part of its values
      if v_key is not null then
        if exists (select 1 from jsonb_each(v_key) as k where coalesce(v_vals, '{}'::jsonb) ? k.key and v_vals -> k.key <> k.value) then
          raise exception 'planner_save: change %: the key and the values disagree', i using errcode = '22023';
        end if;
        v_vals := coalesce(v_vals, '{}'::jsonb) || v_key;
      end if;
      if coalesce(v_vals, '{}'::jsonb) = '{}'::jsonb then
        raise exception 'planner_save: change %: an insert needs values', i using errcode = '22023';
      end if;
    elsif v_op = 'update' then
      if coalesce(v_vals, '{}'::jsonb) = '{}'::jsonb and v_take is null then
        raise exception 'planner_save: change %: an update needs values', i using errcode = '22023';
      end if;
    elsif coalesce(v_vals, '{}'::jsonb) <> '{}'::jsonb then
      raise exception 'planner_save: change %: a delete takes no values', i using errcode = '22023';
    end if;
    select string_agg(k, ', ' order by k) into v_bad
      from jsonb_object_keys(coalesce(v_vals, '{}'::jsonb)) as k
     where not (k = any (v_cols));
    if v_bad is not null then
      raise exception 'planner_save: change %: % has no column %', i, v_table, v_bad using errcode = '22023';
    end if;
    if coalesce(v_vals, '{}'::jsonb) ? 'updated_at' then
      raise exception 'planner_save: change %: updated_at is set by the database', i using errcode = '22023';
    end if;

    -- "as": an insert names the row it makes, for a later change's "from"; its table needs a one-column key
    if c ? 'as' and c -> 'as' <> 'null'::jsonb then
      v_as := c ->> 'as';
      if jsonb_typeof(c -> 'as') <> 'string' or v_as = '' then
        raise exception 'planner_save: change %: as must be a name, e.g. "new-todo"', i using errcode = '22023';
      end if;
      if v_op <> 'insert' then
        raise exception 'planner_save: change %: only an insert can be named (as)', i using errcode = '22023';
      end if;
      if v_named ? v_as then
        raise exception 'planner_save: change %: the name % is used twice', i, v_as using errcode = '22023';
      end if;
      if coalesce(array_length(v_pk, 1), 0) <> 1 then
        raise exception 'planner_save: change %: % is keyed by more than one column, so no other change can take its key', i, v_table
          using errcode = '22023';
      end if;
      v_named := v_named || jsonb_build_object(v_as, v_pk[1]);
    else
      v_as := null;
    end if;
    v_list := v_list || jsonb_build_array(jsonb_build_object('n', i, 'table', v_table, 'op', v_op, 'key', v_key,
                                                             'values', v_vals, 'base', c ->> 'base', 'pk', to_jsonb(v_pk),
                                                             'as', v_as, 'from', v_take));
  end loop;

  -- 2. the rows to change or remove, locked in one order (table, then key) so two saves can't deadlock, each checked
  --    against its base. Saves of the old planner and other chats' items take the same lock, so they queue too.
  select x.id into w from public.worlds x where x.is_default;
  perform pg_advisory_xact_lock(hashtextextended('equinox planner world', w));
  for c in select e.value from jsonb_array_elements(v_list) as e
            where e.value ->> 'op' <> 'insert' order by e.value ->> 'table', (e.value -> 'key')::text loop
    select string_agg(format('t.%1$I = k.%1$I', p), ' and ') into v_where from jsonb_array_elements_text(c -> 'pk') as p;
    execute format('select to_jsonb(t), t.updated_at from public.%1$I t, pg_catalog.jsonb_populate_record(null::public.%1$I, $1) k '
                   'where %2$s for update of t', c ->> 'table', v_where)
       into v_row, v_at using c -> 'key';
    if v_row is null or v_at is distinct from (c ->> 'base')::timestamptz then
      v_clashes := v_clashes || jsonb_build_array(jsonb_build_object('table', c ->> 'table', 'key', c -> 'key', 'current', v_row));
    end if;
  end loop;
  if jsonb_array_length(v_clashes) > 0 then
    return jsonb_build_object('ok', false, 'clashes', v_clashes);
  end if;

  -- 3. the writes, in the order given, as actor planner with the tab's ID
  perform set_config('equinox.actor', 'planner', true), set_config('equinox.actor_detail', coalesce(p_client, ''), true);
  for c in select e.value from jsonb_array_elements(v_list) as e order by (e.value ->> 'n')::bigint loop
    v_table := c ->> 'table';
    -- the values, with each "from" column given the key its named insert made
    v_vals := coalesce(c -> 'values', '{}'::jsonb);
    if jsonb_typeof(c -> 'from') = 'object' then
      v_vals := v_vals || (select jsonb_object_agg(e.key, v_made -> (e.value #>> '{}')) from jsonb_each(c -> 'from') as e);
    end if;
    select string_agg(format('t.%1$I = k.%1$I', p), ' and ') into v_where from jsonb_array_elements_text(c -> 'pk') as p;
    if c ->> 'op' = 'insert' then
      select string_agg(format('%I', k), ', ' order by k), string_agg(format('r.%I', k), ', ' order by k)
        into v_names, v_from from jsonb_object_keys(v_vals) as k;
      execute format('insert into public.%1$I as t (%2$s) select %3$s from pg_catalog.jsonb_populate_record(null::public.%1$I, $1) r '
                     'returning to_jsonb(t), t.updated_at', v_table, v_names, v_from)
         into v_row, v_at using v_vals;
    elsif c ->> 'op' = 'update' then
      select string_agg(format('%1$I = r.%1$I', k), ', ' order by k) into v_names from jsonb_object_keys(v_vals) as k;
      execute format('update public.%1$I t set %2$s from pg_catalog.jsonb_populate_record(null::public.%1$I, $1) r, '
                     'pg_catalog.jsonb_populate_record(null::public.%1$I, $2) k where %3$s returning to_jsonb(t), t.updated_at',
                     v_table, v_names, v_where)
         into v_row, v_at using v_vals, c -> 'key';
    else
      execute format('delete from public.%1$I t using pg_catalog.jsonb_populate_record(null::public.%1$I, $1) k where %2$s '
                     'returning to_jsonb(t)', v_table, v_where)
         into v_row using c -> 'key';
      v_at := null;
    end if;
    if v_row is null then
      raise exception 'planner_save: change %: the row wasn''t there to %', c ->> 'n', c ->> 'op';
    end if;
    if c ->> 'as' is not null then
      v_made := v_made || jsonb_build_object(c ->> 'as', v_row -> (c -> 'pk' ->> 0));
    end if;
    v_rows := v_rows || jsonb_build_array(jsonb_build_object(
      'table', v_table, 'op', c ->> 'op',
      'key', (select jsonb_object_agg(p, v_row -> p) from jsonb_array_elements_text(c -> 'pk') as p),
      'updated_at', to_jsonb(v_at)));
  end loop;
  perform set_config('equinox.actor', coalesce(v_actor, ''), true), set_config('equinox.actor_detail', coalesce(v_detail, ''), true);
  return jsonb_build_object('ok', true, 'rows', v_rows);
end
$function$;

-- ============================================================ 3. the airports' website names and city photos, as data
-- The website's lists (web/assets/site.js CITYPHOTO and NAMES before this change; the planner's Photos kept the same
-- copies), word for word: photo, the city whose photo (site_content media photos) an airport without its own takes;
-- name, the name the website gives an airport, else its city.
insert into public.site_content (key, value)
values ('airport_cities', $airport_cities$
{
 "name": {
  "CDG": "Paris", "ORY": "Paris Orly", "LHR": "London Heathrow", "LGW": "London Gatwick", "STN": "London Stansted",
  "LTN": "London Luton", "JFK": "New York JFK", "EWR": "Newark", "LGA": "New York LaGuardia", "KUL": "Kuala Lumpur",
  "MXP": "Milan", "LIN": "Milan Linate", "PVG": "Shanghai", "SHA": "Shanghai Hongqiao", "PEK": "Beijing",
  "PKX": "Beijing Daxing", "DEL": "Delhi", "BOM": "Mumbai", "HND": "Tokyo Haneda", "NRT": "Tokyo Narita",
  "BKK": "Bangkok", "DMK": "Bangkok Don Mueang", "XIY": "Xi'an", "ORD": "Chicago", "IAD": "Washington Dulles",
  "DCA": "Washington", "DFW": "Dallas–Fort Worth", "MAN": "Manchester", "EDI": "Edinburgh", "AMS": "Amsterdam",
  "KTI": "Phnom Penh", "GOI": "Goa", "COK": "Kochi", "BLR": "Bengaluru", "MAA": "Chennai", "CCU": "Kolkata",
  "HYD": "Hyderabad", "SZX": "Shenzhen", "CAN": "Guangzhou", "KMG": "Kunming", "CTU": "Chengdu",
  "TFU": "Chengdu Tianfu", "CKG": "Chongqing", "HGH": "Hangzhou", "ICN": "Seoul", "CGK": "Jakarta", "DPS": "Bali",
  "SIN": "Singapore", "HKG": "Hong Kong", "MNL": "Manila", "SGN": "Ho Chi Minh City", "HAN": "Hanoi",
  "IST": "Istanbul", "CAI": "Cairo", "DXB": "Dubai", "FCO": "Rome", "BCN": "Barcelona", "MAD": "Madrid",
  "LIS": "Lisbon", "MUC": "Munich", "FRA": "Frankfurt", "ZRH": "Zurich", "VIE": "Vienna", "CPH": "Copenhagen",
  "OSL": "Oslo", "ARN": "Stockholm", "DUB": "Dublin", "BRU": "Brussels", "PRG": "Prague", "BUD": "Budapest",
  "WAW": "Warsaw", "KRK": "Krakow", "ATH": "Athens", "NCE": "Nice", "LYS": "Lyon", "MRS": "Marseille",
  "TLS": "Toulouse", "AGP": "Malaga", "PMI": "Palma de Mallorca", "VLC": "Valencia", "OPO": "Porto", "NAP": "Naples",
  "VCE": "Venice", "CGN": "Cologne", "BER": "Berlin", "GVA": "Geneva", "YYZ": "Toronto", "MEX": "Mexico City",
  "CUN": "Cancún", "LAX": "Los Angeles", "SFO": "San Francisco", "SEA": "Seattle", "MIA": "Miami", "ATL": "Atlanta",
  "BOS": "Boston", "DEN": "Denver", "CLT": "Charlotte", "DTW": "Detroit", "BNA": "Nashville", "MCO": "Orlando"
 },
 "photo": {
  "JFK": "New York", "LGA": "New York", "EWR": "New York", "LHR": "London", "LGW": "London", "CDG": "Paris",
  "AMS": "Amsterdam", "DEL": "Delhi", "BOM": "Mumbai", "PVG": "Shanghai", "PEK": "Beijing", "PKX": "Beijing",
  "KUL": "Kuala Lumpur", "HKG": "Hong Kong", "BKK": "Bangkok", "DMK": "Bangkok", "BCN": "Barcelona", "FCO": "Rome",
  "IST": "Istanbul", "DPS": "Bali", "HND": "Tokyo", "NRT": "Tokyo", "COK": "Kochi", "CGK": "Jakarta", "CAI": "Cairo",
  "MAD": "Madrid", "LIS": "Lisbon", "ORD": "Chicago", "EDI": "Edinburgh", "DUB": "Dublin", "VCE": "Venice",
  "PRG": "Prague", "HGH": "Hangzhou", "GOI": "Goa", "HKT": "Phuket", "SIN": "Singapore"
 }
}
$airport_cities$::jsonb)
on conflict (key) do nothing;

do $check$
declare v jsonb := (select c.value from public.site_content c where c.key = 'airport_cities');
begin
  if v is null or jsonb_typeof(v -> 'name') <> 'object' or jsonb_typeof(v -> 'photo') <> 'object' then
    raise exception 'site_content airport_cities isn''t {name: {...}, photo: {...}}';
  end if;
  raise notice 'the airports'' website words as data: % names, % city photos; site_public() carries them as content.airport_cities',
    (select count(*) from jsonb_object_keys(v -> 'name')), (select count(*) from jsonb_object_keys(v -> 'photo'));
end
$check$;

-- ============================================================ 4. descriptions (decision #10)
comment on column public.aircraft_types.order_config_id is 'The cabin layout an order of the type comes with (private.fig_order_cabin(): Tails, the cash forecast, the briefing), for every airline without its own in airline_order_cabins; empty for none. Filled on 15 Oct from the old rule (the old planner''s DEFAULT_CABIN), changed in Reference';
comment on table public.airline_order_cabins is 'An airline''s own order cabin for an aircraft type, where it differs from the type''s (aircraft_types.order_config_id): Ryanair''s Standard layouts, as a low-cost airline. Filled on 15 Oct from the old rule (the old planner''s DEFAULT_CABIN), changed in Reference. One of the planner tables.';
comment on column public.airline_order_cabins.order_config_id is 'The cabin layout this airline''s orders of the type come with; empty for none';
comment on function private.fig_order_cabin(bigint, bigint) is 'The captured figures (#19): the cabin layout an order of a type comes with for an airline, as data since 15 Oct (spec 2026-10-15 last leftovers §1): the airline''s own (airline_order_cabins), else the type''s (aircraft_types.order_config_id); null for an airline or type that isn''t there. Before, worked out from the cabin names (the old planner''s DEFAULT_CABIN: Standard for a low-cost airline, else Leisure, else Comfort; the airline''s market default among two of the same cabin, then the newest), which filled the data.';
comment on function public.order_cabin(bigint, bigint) is 'The cabin layout an order of a type comes with for an airline (decision #18, build pull request 7; private.fig_order_cabin(), since 15 Oct the data Reference changes: the airline''s own in airline_order_cabins, else the type''s aircraft_types.order_config_id, filled from the old planner''s DEFAULT_CABIN): {id, code, cabin, cost, aircraft_type_id}, or null when there is none. Filing an aircraft into the planner logs its first cabin fit at this cost when the order names no cabin of its own (the old filePlan and cabinCostM). Staff only; runs as owner and checks the caller itself.';
comment on function public.planner_save(jsonb, text) is 'The new planner''s one way to write (decision #18, design §6): one call per action, with every row it changes, as a list of {table, op (insert, update or delete), key (the primary key, e.g. {"id": 812}), base (the row''s updated_at as loaded; needed for an update or delete), values (the columns to set)}. An insert may name the row it makes (as: a name), and a later change in the same call may take a column''s value from that row''s key (from: {column: name}), so a to-do and its steps are one action. All or nothing: if any row to update or delete was changed or removed since it was loaded, nothing is written and the answer is {ok: false, clashes: [{table, key, current (the row now, or null if it''s gone)}]}; otherwise {ok: true, rows: [{table, op, key, updated_at}]}, inserts included. Only the 33 planner tables the change log covers (airline_order_cabins since 15 Oct), and only their own columns; their checks still apply. Written as actor planner with p_client (the tab''s ID) as the detail. Staff only; runs as owner and checks the caller itself.';
comment on table public.site_content is 'Website content kept as data, one row per key: media (destination photos and airline logos), airport_cities (since 15 Oct: name, the name the website gives an airport, and photo, the city whose photo an airport without its own takes; the website and the planner''s Photos screen read them through site_public(), where each kept them in its code before), markets, and mct (minimum connection times, also used by the schedule optimiser; since #13''s pull request 8 site_admin() writes them to world_airports too, and site_public() reads them from there; this copy is kept for the planner''s Reference, which shows it). Written by site_admin() and the planner''s Photos screen. Read by site_public() and site_investor().';
comment on function public.site_public() is 'Everything the public website shows, in one call: hubs and focus cities an airline flies from, aircraft flying (status active, in the order they were added, as the planner''s Tails lists them, since the clean-up), the week''s frequencies (local times), signed interlines, posts, the reports list, site_content (photos, logos, and since 15 Oct the airports'' website names and city photos, content.airport_cities), the minimum connection times (content.mct) and the longest wait for a connection (content.connection_max_wait_h, hours, from settings; the trip search''s window with the planning library, #19), built from the tables (#13, pull request 8), plus our airlines (names, codes, colours, the website''s text, display order) from airlines. updated_at: when the planner''s data last changed (the latest change in the change log for the world, or to airports and countries). No bank or transfer times, cabin layouts or aircraft on order (6 Oct). Anyone may call it; runs as owner.';

select set_config('equinox.actor', '', true), set_config('equinox.actor_detail', '', true);

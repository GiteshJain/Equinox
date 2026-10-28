-- Long haul in 7-day lines: lines in the planner (28 Oct 2026; spec docs/specs/2026-10-27-long-haul-lines.md §2; brief
-- docs/briefs/2026-10-27-long-haul-lines.md, option B; manual §4, under Decided, not yet built until the last pull
-- request of the build merges). Build pull request 2 of 4, after the line optimiser (pull request 1).
--
-- Why: a route beyond about 7,750 km is flown by a 7-day rotating line, 7 aircraft of one type at one airline each a day
-- apart, so every flight on it operates daily. The line optimiser answers with the line; the planner now keeps it, and
-- each aircraft's plan card says which line it flies and which day it starts on.
--
-- Adds two planner tables, two columns and one trigger function, and replaces two functions with the same arguments.
-- Takes nothing away from anyone and moves no captured figure, so it can be applied from the chat:
--   plan_lines (new planner table, the 34th: staff read and write, logged, as the other 33): a line, one row each. Its
--     airline, aircraft type, name (unique within the airline), a note, and the optimiser run it came from
--     (optimiser_answer: the whole answer of optimise-line as jsonb, kept as the record of the run; empty for a line
--     built by hand). The legs are the truth, not the kept answer.
--   plan_line_legs (the 35th, the same access): the line's legs, one row each, in flying order (position), with the line
--     day each departs on (1 to 7, the first aircraft's UTC weekday), flight number, airports, departure (UTC minutes),
--     block and service code, as plan_card_legs keeps a card's. Child rows rather than jsonb, because the planner shows
--     them and the card check reads them, as plan_card_legs.
--   plan_cards.line_id and plan_cards.line_day_offset: the line a card's aircraft flies and its place on it (offset 0 to
--     6: aircraft k of the spec's formula is offset k − 1; it flies line day d on UTC weekday ((d + offset − 1) mod 7) + 1),
--     both set or both empty. One card per line and offset among cards whose aircraft isn't retired (a retired
--     aircraft's card stays as the record and frees its place): private.plan_line_slot(), on plan_cards and on an
--     aircraft coming back from retired, under a lock on the line so two writers can't both take a place.
--   planner_save(p_changes, p_client): exactly as 20261015220000_last_leftovers.sql left it, with plan_lines and
--     plan_line_legs on its list of tables (35).
--   private.rules_input_doc(p_world_id, p_routes): as 20261021180000 left it, with each aircraft type's reach (range_km,
--     aircraft_types since 19 Oct), so optimise-line needs no --range. The lines aren't in it: the planner reads the
--     tables (as it reads plan cards), and the line check takes the cards.
-- A line's size is settings.line_aircraft (7; the game repeats each aircraft's week, so a rotating line is exactly 7).
-- Order after "merge": apply this, then merge (the planner live today ignores the new tables and columns).

select set_config('equinox.actor', 'migration', true),
       set_config('equinox.actor_detail', '20261028180000_plan_lines', true);

-- ============================================================ 1. the lines and their legs
create table public.plan_lines (
  id bigint generated always as identity primary key,
  world_id bigint not null references public.worlds (id),
  airline_id bigint not null,
  aircraft_type_id bigint not null,
  name text not null constraint plan_lines_name_check check (btrim(name) <> ''),
  note text,
  optimiser_answer jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint plan_lines_id_world_key unique (id, world_id),
  constraint plan_lines_airline_name_key unique (airline_id, name),
  constraint plan_lines_airline_fkey foreign key (airline_id, world_id) references public.airlines (id, world_id),
  constraint plan_lines_type_fkey foreign key (aircraft_type_id, world_id) references public.aircraft_types (id, world_id)
);
create index plan_lines_world_id_idx on public.plan_lines (world_id);
create index plan_lines_aircraft_type_id_idx on public.plan_lines (aircraft_type_id);

create table public.plan_line_legs (
  id bigint generated always as identity primary key,
  world_id bigint not null references public.worlds (id),
  line_id bigint not null,
  position int not null constraint plan_line_legs_position_check check (position >= 1),
  line_day smallint not null constraint plan_line_legs_line_day_check check (line_day between 1 and 7),
  flight_no int,
  origin_code text not null references public.airports (code),
  dest_code text not null references public.airports (code),
  dep_utc_min smallint not null constraint plan_line_legs_dep_utc_min_check check (dep_utc_min between 0 and 1439),
  block_min smallint constraint plan_line_legs_block_min_check check (block_min > 0),
  service_code text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint plan_line_legs_line_position_key unique (line_id, position),
  constraint plan_line_legs_line_fkey foreign key (line_id, world_id) references public.plan_lines (id, world_id) on delete cascade
);
create index plan_line_legs_world_id_idx on public.plan_line_legs (world_id);
create index plan_line_legs_origin_code_idx on public.plan_line_legs (origin_code);
create index plan_line_legs_dest_code_idx on public.plan_line_legs (dest_code);

-- as every planner table (20261009210000_planner_tables.sql): RLS with one staff rule per action (the check once per
-- query), nothing for anon, authenticated reads and writes (the rules decide who), updated_at by trigger, every change
-- logged (manual §1: a new table grants its own access)
alter table public.plan_lines enable row level security;
create policy "staff read" on public.plan_lines for select to authenticated using ((select public.is_planner_user()));
create policy "staff add" on public.plan_lines for insert to authenticated with check ((select public.is_planner_user()));
create policy "staff change" on public.plan_lines for update to authenticated using ((select public.is_planner_user())) with check ((select public.is_planner_user()));
create policy "staff remove" on public.plan_lines for delete to authenticated using ((select public.is_planner_user()));
revoke all on table public.plan_lines from public, anon, authenticated;
grant select, insert, update, delete on table public.plan_lines to authenticated;
create trigger set_updated_at before insert or update on public.plan_lines for each row execute function private.set_updated_at();
create trigger log_change after insert or update or delete on public.plan_lines for each row execute function private.log_change();

alter table public.plan_line_legs enable row level security;
create policy "staff read" on public.plan_line_legs for select to authenticated using ((select public.is_planner_user()));
create policy "staff add" on public.plan_line_legs for insert to authenticated with check ((select public.is_planner_user()));
create policy "staff change" on public.plan_line_legs for update to authenticated using ((select public.is_planner_user())) with check ((select public.is_planner_user()));
create policy "staff remove" on public.plan_line_legs for delete to authenticated using ((select public.is_planner_user()));
revoke all on table public.plan_line_legs from public, anon, authenticated;
grant select, insert, update, delete on table public.plan_line_legs to authenticated;
create trigger set_updated_at before insert or update on public.plan_line_legs for each row execute function private.set_updated_at();
create trigger log_change after insert or update or delete on public.plan_line_legs for each row execute function private.log_change();

-- ============================================================ 2. a plan card's line and its place on it
alter table public.plan_cards add column line_id bigint;
alter table public.plan_cards add column line_day_offset smallint;
alter table public.plan_cards add constraint plan_cards_line_fkey foreign key (line_id, world_id) references public.plan_lines (id, world_id);
alter table public.plan_cards add constraint plan_cards_line_day_offset_check check (line_day_offset between 0 and 6);
alter table public.plan_cards add constraint plan_cards_line_both_check check ((line_id is null) = (line_day_offset is null));
create index plan_cards_line_id_idx on public.plan_cards (line_id, line_day_offset);

-- one card per line and offset among cards whose aircraft isn't retired; on plan_cards before a card takes a place, and
-- on aircraft after one comes back from retired. A lock on the line, so two writers can't both take the same place.
create or replace function private.plan_line_slot()
 returns trigger
 language plpgsql
 set search_path to ''
as $function$
declare
  v_line bigint;
  v_offset smallint;
  v_card bigint;
  v_reg text;
  v_other text;
begin
  if tg_table_name = 'plan_cards' then
    if new.line_id is null then return new; end if;
    v_line := new.line_id;
    v_offset := new.line_day_offset;
    v_card := new.id;
    -- a retired aircraft's card is the record of what it flew: it holds no place
    select a.registration into v_reg from public.aircraft a where a.id = new.aircraft_id and a.status <> 'retired';
    if not found then return new; end if;
  else
    -- an aircraft back from retired takes its card's place again, if it's free
    select c.line_id, c.line_day_offset, c.id into v_line, v_offset, v_card
      from public.plan_cards c where c.aircraft_id = new.id and c.line_id is not null;
    if not found then return new; end if;
    v_reg := new.registration;
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('equinox plan line', v_line));
  select a.registration into v_other
    from public.plan_cards c join public.aircraft a on a.id = c.aircraft_id
   where c.line_id = v_line and c.line_day_offset = v_offset and c.id <> v_card and a.status <> 'retired'
   limit 1;
  if found then
    raise exception 'line % already has aircraft % at offset %, so % can''t take it', v_line, v_other, v_offset, v_reg
      using errcode = 'unique_violation';
  end if;
  return new;
end
$function$;
revoke all on function private.plan_line_slot() from public, anon, authenticated;
create trigger plan_line_slot before insert or update of line_id, line_day_offset, aircraft_id on public.plan_cards
  for each row execute function private.plan_line_slot();
create trigger plan_line_slot after update of status on public.aircraft
  for each row when (old.status = 'retired' and new.status <> 'retired') execute function private.plan_line_slot();

-- ============================================================ 3. planner_save(): the two new tables on its list
-- As 20261015220000_last_leftovers.sql left it, with the 34th and 35th planner tables.
create or replace function public.planner_save(p_changes jsonb, p_client text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  -- the 35 planner tables, each with the change-log trigger (migration 20261009210000_planner_tables.sql, §4; the 33rd,
  -- airline_order_cabins, 20261015220000_last_leftovers.sql; the 34th and 35th, plan_lines and plan_line_legs,
  -- 20261028180000_plan_lines.sql)
  v_tables constant text[] := array[
    'worlds', 'groups', 'airlines', 'airline_bases', 'airline_aircraft_types',
    'countries', 'airports', 'world_airports',
    'aircraft_types', 'cabin_configs', 'aircraft', 'aircraft_cabin_keeps',
    'markets', 'service_profiles', 'routes', 'rotations', 'flight_legs',
    'plan_cards', 'plan_card_legs',
    'todos', 'todo_items', 'growth_log', 'spending_log', 'fare_plan', 'interline_agreements', 'monthly_checks',
    'dismissals', 'cash_entries', 'load_entries', 'load_days',
    'settings', 'world_rules', 'airline_order_cabins', 'plan_lines', 'plan_line_legs'];
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
      raise exception 'planner_save: change %: % isn''t one of the planner''s tables (only the 35 the change log covers)',
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
$function$
;

-- ============================================================ 4. rules_input(): each type's reach
-- As 20261021180000_cabins_new_rule.sql left it, with aircraft_types.range_km in each type.
create or replace function private.rules_input_doc(p_world_id bigint, p_routes text DEFAULT 'all'::text)
 returns jsonb
 language plpgsql
 stable
 set search_path to ''
as $function$
declare
  w bigint;
  v_name text;
begin
  if p_routes is null or p_routes not in ('all', 'flown') then
    raise exception 'rules_input: p_routes must be all or flown, not %', coalesce(p_routes, 'null') using errcode = '22023';
  end if;
  select x.id, x.name into w, v_name from public.worlds x where x.id = p_world_id or (p_world_id is null and x.is_default);
  if w is null then raise exception 'no such world: %', coalesce(p_world_id::text, 'no default world') using errcode = '22023'; end if;
  return (
    with
    -- the routes the document holds: every route that isn't removed, or with 'flown' only those that have rotations
    rts as (
      select r.* from public.routes r
       where r.world_id = w and not r.removed
         and (p_routes = 'all' or exists (select 1 from public.rotations ro where ro.route_id = r.id))),
    -- the airlines the planning rows name, and every airline of our groups (the same with 'all' and 'flown')
    named(id) as (
      select b.airline_id from public.airline_bases b where b.world_id = w
      union select a.airline_id from public.aircraft a where a.world_id = w
      union select r.airline_id from public.routes r where r.world_id = w and not r.removed
      union select r.airline_id from public.rotations r where r.world_id = w
      union select l.airline_id from public.flight_legs l where l.world_id = w
      union select al.id from public.airlines al join public.groups g on g.id = al.group_id and g.world_id = al.world_id
             where al.world_id = w and g.kind = 'ours'),
    -- every airport the document's routes, a leg, a base or an aircraft's base uses
    codes(code) as (
      select r.hub_code from rts r
      union select r.dest_code from rts r
      union select l.origin_code from public.flight_legs l where l.world_id = w
      union select l.dest_code from public.flight_legs l where l.world_id = w
      union select b.airport_code from public.airline_bases b where b.world_id = w
      union select a.base_code from public.aircraft a where a.world_id = w and a.base_code is not null)
    select jsonb_build_object(
      'world', jsonb_build_object('id', w, 'name', v_name),
      'settings', (select coalesce(jsonb_object_agg(s.key, s.value order by s.key), '{}'::jsonb)
                     from public.settings s where s.world_id = w and s.airline_id is null),
      'world_rules', (select coalesce(jsonb_object_agg(r.key, r.value order by r.key), '{}'::jsonb)
                        from public.world_rules r where r.world_id = w),
      -- each type with its reach, range_km since 28 Oct (the line optimiser's reach check, spec 2026-10-27 long-haul lines §2)
      'aircraft_types', (select coalesce(jsonb_agg(jsonb_build_object(
                            'id', t.id, 'name', t.name, 'family_no', t.family_no, 'seats_max', t.seats_max, 'cruise_kmh', t.cruise_kmh,
                            'min_turn_min', t.min_turn_min, 'gap_target_h', t.gap_target_h, 'maint_per_cycle', t.maint_per_cycle,
                            'maint_per_hour', t.maint_per_hour, 'ground_keep_min', t.ground_keep_min, 'range_km', t.range_km) order by t.id), '[]'::jsonb)
                           from public.aircraft_types t where t.world_id = w),
      -- each layout with its name (cabin: Standard, Leisure, Leisure Plus or Comfort; since 21 Oct, for the plan card's cabin)
      'cabin_configs', (select coalesce(jsonb_agg(jsonb_build_object(
                           'id', c.id, 'code', c.code, 'aircraft_type_id', c.aircraft_type_id, 'seats', c.seats, 'cabin', c.cabin) order by c.id), '[]'::jsonb)
                          from public.cabin_configs c where c.world_id = w),
      -- each airport with its country's region (countries.region, #18 build pull request 12); none without a country
      'airports', (select coalesce(jsonb_agg(jsonb_build_object(
                      'code', k.code, 'city', a.city, 'country_code', a.country_code, 'region', co.region, 'lat', a.lat, 'lon', a.lon,
                      'utc_offset', coalesce(wa.utc_offset_override, a.utc_offset), 'utc_offset_override', wa.utc_offset_override,
                      'mct_min', wa.mct_min, 'night_ban_from', to_char(wa.night_ban_from, 'HH24:MI'), 'night_ban_to', to_char(wa.night_ban_to, 'HH24:MI'),
                      'closed', coalesce(wa.closed, false)) order by k.code collate "C"), '[]'::jsonb)
                     from codes k
                     left join public.airports a on a.code = k.code
                     left join public.countries co on co.code = a.country_code
                     left join public.world_airports wa on wa.world_id = w and wa.airport_code = k.code),
      -- is_lcc since 21 Oct: a low-cost airline flies Standard layouts only (manual §5)
      'airlines', (select coalesce(jsonb_agg(jsonb_build_object(
                      'id', al.id, 'iata_code', al.iata_code, 'game_id', al.game_id, 'game_name', al.game_name, 'planner_name', al.planner_name,
                      'public_name', al.public_name, 'position', al.position, 'active', al.active, 'ours', coalesce(g.kind = 'ours', false),
                      'is_lcc', coalesce(al.is_lcc, false),
                      -- the settings as they apply to this airline: its own override of a key in place of the world's value
                      'settings', (select coalesce(jsonb_object_agg(s.key, s.value order by s.key), '{}'::jsonb)
                                     from (select distinct on (st.key) st.key, st.value from public.settings st
                                            where st.world_id = w and (st.airline_id is null or st.airline_id = al.id)
                                            order by st.key, st.airline_id nulls last) s))
                      order by al.position nulls last, al.id), '[]'::jsonb)
                     from public.airlines al
                     left join public.groups g on g.id = al.group_id and g.world_id = al.world_id
                    where al.world_id = w and al.id in (select n.id from named n)),
      'airline_bases', (select coalesce(jsonb_agg(jsonb_build_object(
                           'id', b.id, 'airline_id', b.airline_id, 'airport_code', b.airport_code, 'role', b.role, 'is_main', b.is_main,
                           'parent_base_id', b.parent_base_id, 'parent_code', pb.airport_code,
                           'bank_times', (select jsonb_agg(to_char(t, 'HH24:MI') order by o) from unnest(b.bank_times) with ordinality as u(t, o)),
                           'flight_no_from', b.flight_no_from, 'last_flight_no', b.last_flight_no, 'position', b.position)
                           order by b.position nulls last, b.id), '[]'::jsonb)
                          from public.airline_bases b left join public.airline_bases pb on pb.id = b.parent_base_id
                         where b.world_id = w),
      'aircraft', (select coalesce(jsonb_agg(jsonb_build_object(
                      'id', a.id, 'registration', a.registration, 'airline_id', a.airline_id, 'aircraft_type_id', a.aircraft_type_id,
                      'cabin_config_id', a.cabin_config_id, 'base_code', a.base_code, 'status', a.status) order by a.id), '[]'::jsonb)
                     from public.aircraft a where a.world_id = w),
      -- each route with its market (any override applied) and, since 21 Oct, the layout it calls for: its own cabin_choice
      -- and its market's layout
      'routes', (select coalesce(jsonb_agg(jsonb_build_object(
                    'id', r.id, 'airline_id', r.airline_id, 'hub_code', r.hub_code, 'dest_code', r.dest_code,
                    'distance_km', coalesce(r.distance_override_km, r.distance_km),
                    'market_id', m.id, 'market', m.name, 'market_layout', m.layout, 'cabin_choice', r.cabin_choice) order by r.id), '[]'::jsonb)
                   from rts r
                   left join public.markets m on m.id = case when r.market_cleared then null else coalesce(r.market_override_id, r.market_id) end),
      'rotations', (select coalesce(jsonb_agg(jsonb_build_object(
                       'id', r.id, 'airline_id', r.airline_id, 'route_id', r.route_id, 'legacy_key', r.legacy_key) order by r.id), '[]'::jsonb)
                      from public.rotations r where r.world_id = w),
      'flight_legs', (select coalesce(jsonb_agg(jsonb_build_object(
                         'id', l.id, 'airline_id', l.airline_id, 'rotation_id', l.rotation_id, 'leg_no', l.leg_no, 'flight_no', l.flight_no,
                         'origin_code', l.origin_code, 'dest_code', l.dest_code, 'aircraft_id', l.aircraft_id, 'days_utc', to_jsonb(l.days_utc),
                         'dep_utc_min', l.dep_utc_min, 'block_min', l.block_min) order by l.rotation_id, l.leg_no, l.id), '[]'::jsonb)
                        from public.flight_legs l where l.world_id = w),
      -- the service profiles (service_profiles), for the plan card's service check (#18 build pull request 10)
      'service_profiles', (select coalesce(jsonb_agg(jsonb_build_object(
                              'id', s.id, 'code', s.code, 'airline_id', s.airline_id, 'up_to_km', s.up_to_km) order by s.id), '[]'::jsonb)
                             from public.service_profiles s where s.world_id = w))
  );
end
$function$
;

-- ============================================================ 5. descriptions
comment on table public.plan_lines is 'A 7-day rotating line (manual §4, long haul in lines; spec docs/specs/2026-10-27-long-haul-lines.md §2): 7 aircraft of one type at one airline fly one weekly pattern, each a day apart, so every flight on it operates daily at the same time. Its legs are plan_line_legs; each aircraft''s plan card names the line and its offset (plan_cards.line_id, line_day_offset). Its size is settings.line_aircraft (7). Written by the Scheduling chat from optimise-line''s answer (scripts/README.md). One of the planner tables.';
comment on column public.plan_lines.airline_id is 'The airline whose aircraft fly the line';
comment on column public.plan_lines.aircraft_type_id is 'The aircraft type every aircraft on the line is';
comment on column public.plan_lines.name is 'What the planner calls it, e.g. "XLR line JFK 1"; unique within the airline';
comment on column public.plan_lines.note is 'Anything worth keeping about the line; empty for none';
comment on column public.plan_lines.optimiser_answer is 'The optimise-line answer the line came from, whole (the run''s settings, search and best line with its 7 cards), kept as the record of the run; the legs are plan_line_legs, not this. Empty for a line built by hand';
comment on table public.plan_line_legs is 'A line''s flights in flying order, with the same time rules as plan_card_legs (UTC): each departs on its line day, and the aircraft at offset k flies line day d on UTC weekday ((d + k − 1) mod 7) + 1 (the library''s card.fromLine). One of the planner tables.';
comment on column public.plan_line_legs.line_id is 'The line (plan_lines)';
comment on column public.plan_line_legs.position is 'Order on the line, as it is flown, from 1';
comment on column public.plan_line_legs.line_day is 'The line day it departs on, 1 to 7: the UTC weekday on the card of the aircraft at offset 0';
comment on column public.plan_line_legs.flight_no is 'Flight number, the same every day it operates';
comment on column public.plan_line_legs.origin_code is 'Where it leaves from';
comment on column public.plan_line_legs.dest_code is 'Where it lands';
comment on column public.plan_line_legs.dep_utc_min is 'Departure, minutes after 00:00 UTC on its line day';
comment on column public.plan_line_legs.block_min is 'Block time, minutes';
comment on column public.plan_line_legs.service_code is 'Service code: S1, S2, …, or Ryanair''s R';
comment on column public.plan_cards.line_id is 'The 7-day line the aircraft flies (plan_lines), or empty for a card of its own';
comment on column public.plan_cards.line_day_offset is 'Its place on the line, 0 to 6 (aircraft k of the spec''s formula is offset k − 1): it flies line day d on UTC weekday ((d + offset − 1) mod 7) + 1. Set with line_id; one card per line and offset among aircraft that aren''t retired';
comment on function private.plan_line_slot() is 'Trigger on plan_cards and aircraft (spec 2026-10-27 long-haul lines §2): refuses a second card at a line''s offset while the aircraft of the first isn''t retired. A retired aircraft''s card holds no place, so its replacement can take it; an aircraft coming back from retired is refused if its place was taken. Takes a lock on the line so two writers can''t both take a place.';
comment on function public.planner_save(jsonb, text) is 'The new planner''s one way to write (decision #18, design §6): one call per action, with every row it changes, as a list of {table, op (insert, update or delete), key (the primary key, e.g. {"id": 812}), base (the row''s updated_at as loaded; needed for an update or delete), values (the columns to set)}. An insert may name the row it makes (as: a name), and a later change in the same call may take a column''s value from that row''s key (from: {column: name}), so a to-do and its steps are one action. All or nothing: if any row to update or delete was changed or removed since it was loaded, nothing is written and the answer is {ok: false, clashes: [{table, key, current (the row now, or null if it''s gone)}]}; otherwise {ok: true, rows: [{table, op, key, updated_at}]}, inserts included. Only the 35 planner tables the change log covers (airline_order_cabins since 15 Oct, plan_lines and plan_line_legs since 28 Oct), and only their own columns; their checks still apply. Written as actor planner with p_client (the tab''s ID) as the detail. Staff only; runs as owner and checks the caller itself.';
comment on function public.rules_input(bigint, text) is 'Everything the planning library (lib/rules/, decision #19, design §7) needs, in one JSON document for the world (the default world when null): settings (the world''s values) and world_rules, as key → value; aircraft_types (cruise, turn, maintenance per cycle and hour, ground keep, seats and, since 28 Oct, reach: range_km, for the line optimiser); cabin_configs (code, type, seats and, since 21 Oct, the layout''s name, cabin); every airport any route, leg or base uses (position, country and its region, UTC offset with the world''s correction applied, minimum connection time, night ban as local HH:MM); airlines (ours and any the planning rows name, whether low cost: is_lcc), each with its settings as they apply to it (its own overrides in place of the world''s values); airline_bases (role, bank times as HH:MM, flight-number block, last number used); aircraft; routes that aren''t removed (distance and market with any override applied, and since 21 Oct the market''s layout, market_layout, and the route''s own cabin_choice, for the plan card''s cabin); rotations; flight_legs (UTC weekdays, departure minute and block time), by rotation and leg; and service_profiles (code, airline or none for the shared ones, up to km), for the plan card''s service check (#18 build pull request 10). p_routes: all (the default) or flown, the new planner''s lighter start (#18, design §5): only the routes that have rotations, and only the airports they, the legs, the bases and the aircraft use; the rest of the document is the same. The new planner (flown), the scripts (export_for_report(''rules''), all) and Claude''s command (node lib/rules/dist/cli.js) build the library''s Rules object from it. Staff only; runs as owner and checks the caller itself.';

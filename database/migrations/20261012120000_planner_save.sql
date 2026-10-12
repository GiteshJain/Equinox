-- planner_save(): how the new planner writes (decision #18, build pull request 1, "the shell").
-- Design: docs/design/2026-10-12-planner-app.md §6 (saving) and §14 choice 4. Spec: docs/specs/2026-10-12-planner-shell.md §5.
--
-- Adds one function; changes and removes nothing. The old planner keeps saving through the adapter until the switch
-- (design §11), so nothing calls this yet except the new planner at /planner/next/ and the checks.
--   public.planner_save(p_changes jsonb, p_client text): one call per action, with every row the action changes. Each
--   change names its table, op (insert, update or delete), key (the primary key), base (the row's updated_at as it was
--   loaded, for an update or delete) and values (the columns to set). All or nothing: if any row to update or delete
--   was changed or removed since it was loaded, nothing is written and the answer gives those rows as they are now.
--   Written as actor planner, with the tab's ID (p_client) as the detail, so the change log says who (decision #15).
--   Only the 32 planner tables the change log covers; unknown columns are refused; the tables' own checks apply.
--   Staff only; runs as owner with an empty search path, like planner_state_put().

select set_config('equinox.actor', 'migration', true),
       set_config('equinox.actor_detail', '20261012120000_planner_save', true);

create or replace function public.planner_save(p_changes jsonb, p_client text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  -- the 32 planner tables, each with the change-log trigger (migration 20261009210000_planner_tables.sql, §4)
  v_tables constant text[] := array[
    'worlds', 'groups', 'airlines', 'airline_bases', 'airline_aircraft_types',
    'countries', 'airports', 'world_airports',
    'aircraft_types', 'cabin_configs', 'aircraft', 'aircraft_cabin_keeps',
    'markets', 'service_profiles', 'routes', 'rotations', 'flight_legs',
    'plan_cards', 'plan_card_legs',
    'todos', 'todo_items', 'growth_log', 'spending_log', 'fare_plan', 'interline_agreements', 'monthly_checks',
    'dismissals', 'cash_entries', 'load_entries', 'load_days',
    'settings', 'world_rules'];
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
      raise exception 'planner_save: change %: % isn''t one of the planner''s tables (only the 32 the change log covers)',
        i, coalesce(v_table, 'no table') using errcode = '22023';
    end if;
    if v_op is null or v_op not in ('insert', 'update', 'delete') then
      raise exception 'planner_save: change %: op must be insert, update or delete, not %', i, coalesce(v_op, 'nothing')
        using errcode = '22023';
    end if;
    v_key := c -> 'key';
    v_vals := c -> 'values';
    if v_key = 'null'::jsonb then v_key := null; end if;
    if v_vals = 'null'::jsonb then v_vals := null; end if;
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
      if coalesce(v_vals, '{}'::jsonb) = '{}'::jsonb then
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
    v_list := v_list || jsonb_build_array(jsonb_build_object('n', i, 'table', v_table, 'op', v_op, 'key', v_key,
                                                             'values', v_vals, 'base', c ->> 'base', 'pk', to_jsonb(v_pk)));
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
    select string_agg(format('t.%1$I = k.%1$I', p), ' and ') into v_where from jsonb_array_elements_text(c -> 'pk') as p;
    if c ->> 'op' = 'insert' then
      select string_agg(format('%I', k), ', ' order by k), string_agg(format('r.%I', k), ', ' order by k)
        into v_names, v_from from jsonb_object_keys(c -> 'values') as k;
      execute format('insert into public.%1$I as t (%2$s) select %3$s from pg_catalog.jsonb_populate_record(null::public.%1$I, $1) r '
                     'returning to_jsonb(t), t.updated_at', v_table, v_names, v_from)
         into v_row, v_at using c -> 'values';
    elsif c ->> 'op' = 'update' then
      select string_agg(format('%1$I = r.%1$I', k), ', ' order by k) into v_names from jsonb_object_keys(c -> 'values') as k;
      execute format('update public.%1$I t set %2$s from pg_catalog.jsonb_populate_record(null::public.%1$I, $1) r, '
                     'pg_catalog.jsonb_populate_record(null::public.%1$I, $2) k where %3$s returning to_jsonb(t), t.updated_at',
                     v_table, v_names, v_where)
         into v_row, v_at using c -> 'values', c -> 'key';
    else
      execute format('delete from public.%1$I t using pg_catalog.jsonb_populate_record(null::public.%1$I, $1) k where %2$s '
                     'returning to_jsonb(t)', v_table, v_where)
         into v_row using c -> 'key';
      v_at := null;
    end if;
    if v_row is null then
      raise exception 'planner_save: change %: the row wasn''t there to %', c ->> 'n', c ->> 'op';
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

revoke all on function public.planner_save(jsonb, text) from public, anon, authenticated, service_role;
grant execute on function public.planner_save(jsonb, text) to authenticated;

comment on function public.planner_save(jsonb, text) is 'The new planner''s one way to write (decision #18, design §6): one call per action, with every row it changes, as a list of {table, op (insert, update or delete), key (the primary key, e.g. {"id": 812}), base (the row''s updated_at as loaded; needed for an update or delete), values (the columns to set)}. All or nothing: if any row to update or delete was changed or removed since it was loaded, nothing is written and the answer is {ok: false, clashes: [{table, key, current (the row now, or null if it''s gone)}]}; otherwise {ok: true, rows: [{table, op, key, updated_at}]}, inserts included. Only the 32 planner tables the change log covers, and only their own columns; their checks still apply. Written as actor planner with p_client (the tab''s ID) as the detail. Staff only; runs as owner and checks the caller itself.';

select set_config('equinox.actor', '', true), set_config('equinox.actor_detail', '', true);

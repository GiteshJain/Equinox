-- The adapter's write side, run beside the old storage (decision #13, build pull request 5).
-- Design: docs/design/2026-10-09-data-model.md (§3.11, §6, §8, §9, §11 choices 1 and 4). Spec:
-- docs/specs/2026-10-10-adapter-write-side.md.
--
-- Adds, and removes or revokes nothing that exists (so there is no file for Gitesh to run):
--   1. job_runs (design §3.11): one row per run of every job. This pull request writes adapter_mirror and adapter_check
--      rows; moving backup_runs in waits for pull request 7;
--   2. comparing a planner document with the tables, with exactly the differences the tests allow;
--   3. the item engine: a planner document split into items (a tail, a frequency, a to-do, a cash figure ...), the items
--      that differ from the tables, and writers that change only those rows. planner_state_put(), planner_item_put()
--      and planner_item_delete() go through it;
--   4. loads: save_loads() keeps its name, arguments, answer and its writes to planner_loads, and also writes
--      load_entries and load_days;
--   5. side by side (design §9): after every save of planner_state or planner_loads, a trigger copies it into the
--      tables (actor planner, detail mirror) and compares the getters with it. Each mirror and each comparison is one
--      job_runs row; a failure is recorded and never stops the save. adapter_check_days and adapter_clean_days() count
--      the clean days for pull request 9;
--   6. the tables catch up with every save since pull request 4 (private.load_planner() once more), then side by side
--      starts;
--   7. access and descriptions.
-- Apply it when no capture is running.

select set_config('equinox.actor', 'migration', true),
       set_config('equinox.actor_detail', '20261010210000_adapter_write_side', true);

-- ============================================================ 1. job_runs (design §3.11)
create table public.job_runs (
  id bigint generated always as identity primary key,
  job text not null check (job in ('backup', 'snapshot', 'snapshot_fallback', 'cleanup', 'archive', 'adapter_mirror', 'adapter_check')),
  world_id bigint references public.worlds (id),
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  status text not null default 'running' check (status in ('running', 'ok', 'failed', 'incomplete')),
  for_day date,
  for_month date check (for_month = date_trunc('month', for_month)::date),
  note text,
  details jsonb
);
create index job_runs_job_started_idx on public.job_runs (job, started_at desc);
create index job_runs_world_day_idx on public.job_runs (world_id, for_day);
alter table public.job_runs enable row level security;
create policy "staff read" on public.job_runs for select to authenticated using ((select public.is_planner_user()));

-- One job_runs row, finished
create or replace function private.job_run_add(p_job text, p_world_id bigint, p_started_at timestamptz, p_status text,
                                               p_note text, p_details jsonb)
 returns bigint
 language sql
 set search_path to ''
as $function$
  insert into public.job_runs (job, world_id, started_at, finished_at, status, for_day, note, details)
  values (p_job, p_world_id, p_started_at, clock_timestamp(), p_status,
          case when p_world_id is not null then private.capture_day(p_world_id, p_started_at) end, p_note, p_details)
  returning id
$function$;

-- ============================================================ 2. comparing
-- private.planner_json_differences() with one shortcut: two equal values (numbers by value, keys in any order) are
-- passed over without walking into them. The only kind that can hide is "numbers by value", which is allowed anyway,
-- so the differences that count are exactly the same; on a whole document it is many times faster.
create or replace function private.planner_json_diff(p_old jsonb, p_new jsonb, p_path text default '$',
                                                     p_key text default null, p_in_list boolean default false)
 returns table (path text, kind text)
 language plpgsql
 immutable
 set search_path to ''
as $function$
declare k text; i int; n_old int; n_new int;
begin
  if p_old = p_new then return; end if;
  -- a list item that one side doesn't have
  if p_in_list and (p_old is null or p_new is null) then
    if p_old is not null or p_new is not null then return query select p_path, 'differs'; end if;
    return;
  end if;
  if p_key in ('savedAt', 'version') then
    if p_old is distinct from p_new then return query select p_path, 'savedAt and version'; end if;
    return;
  end if;
  -- missing, or null
  if coalesce(p_old, 'null'::jsonb) = 'null'::jsonb and coalesce(p_new, 'null'::jsonb) = 'null'::jsonb then
    if (p_old is null) <> (p_new is null) then return query select p_path, 'a missing key equals null'; end if;
    return;
  end if;
  if p_old is null and p_new = '"Active"'::jsonb and p_path ~ '^\$\.tails\[\d+\]\.status$' then
    return query select p_path, 'a tail with no status equals "Active"';
    return;
  end if;
  if coalesce(p_old, 'null'::jsonb) = 'null'::jsonb or coalesce(p_new, 'null'::jsonb) = 'null'::jsonb then
    return query select p_path, 'differs';
    return;
  end if;
  if p_key in ('noOut', 'noBack', 'no') and jsonb_typeof(p_old) <> jsonb_typeof(p_new)
     and jsonb_typeof(p_old) in ('string', 'number') and jsonb_typeof(p_new) in ('string', 'number') then
    return query select p_path, case when (p_old #>> '{}') = (p_new #>> '{}') then 'flight numbers as text' else 'differs' end;
    return;
  end if;
  if jsonb_typeof(p_old) <> jsonb_typeof(p_new) then
    return query select p_path, 'differs';
    return;
  end if;
  case jsonb_typeof(p_old)
    when 'object' then
      for k in select x from jsonb_object_keys(p_old) as x union select x from jsonb_object_keys(p_new) as x loop
        return query select * from private.planner_json_diff(p_old -> k, p_new -> k, p_path || '.' || k, k, false);
      end loop;
    when 'array' then
      n_old := jsonb_array_length(p_old); n_new := jsonb_array_length(p_new);
      for i in 0 .. greatest(n_old, n_new) - 1 loop
        return query select * from private.planner_json_diff(p_old -> i, p_new -> i, p_path || '[' || i || ']', p_key, true);
      end loop;
    when 'number' then
      if p_old <> p_new then return query select p_path, 'differs';
      elsif p_old::text <> p_new::text then return query select p_path, 'numbers by value';
      end if;
    else
      if p_old <> p_new then return query select p_path, 'differs'; end if;
  end case;
end
$function$;

-- Where a difference is, without the parts that change from item to item: list positions as [], the keys of keyed
-- sections as {}, a loads day as {day} and its flights as {flight}. For notes; the paths themselves go in details.
create or replace function private.planner_place(p_path text)
 returns text
 language sql
 immutable
 set search_path to ''
as $function$
  select regexp_replace(regexp_replace(regexp_replace(regexp_replace(p_path, '\[\d+\]', '[]', 'g'),
           '^(\$\.(plans|cash|fixed7|interline|routeEdits|routeCabin|monthly|dismissed|cabinKeep|ref\.markets|ref\.curfews|ref\.gameLinks|ref\.utcOverrides|ref\.consts))\.[^.\[]+', '\1.{}'),
           '^\$\.\d{4}-\d{2}-\d{2}', '$.{day}'), '\.f\..+$', '.f.{flight}')
$function$;

-- A planner_state document against the one built from the tables, with exactly the differences the tests allow
-- (database/tests/planner_load_state_test.sql): design §9's, plus "cash/fixed7 captured after the planner last saved"
-- (the Building chat's call, 10 Oct). That one holds only for a cash or fixed7 entry whose built figure equals the
-- capture's (capture_cash, rounded as the planner rounds) and whose capture came after p_saved_at: for cash, that
-- airline's balance for the date; for fixed7, that balance or any of the events the figure counts. One row per
-- difference: its path, its kind ('differs' for any that isn't allowed) and, for a cash or fixed7 figure that isn't
-- allowed, why (dates and airlines, never figures).
create or replace function private.planner_state_check(p_world_id bigint, p_old jsonb, p_saved_at bigint, p_new jsonb)
 returns table (path text, kind text, why text)
 language sql
 stable
 set search_path to ''
as $function$
  with d as (select x.path, x.kind from private.planner_json_diff(p_old, p_new) x),
  x as (
    select d.path, m[1] as sec, m[2] as day, m[3] as airline
      from d cross join lateral regexp_match(d.path, '^\$\.(cash|fixed7)\.([^.]+)(?:\.(.+))?$') as m
     where d.kind = 'differs' and m is not null),
  -- every entry behind a difference there, one per airline and date (a whole date differs when one side has none)
  entries as (
    select x.path, x.sec, x.day, x.airline from x where x.airline is not null
    union
    select x.path, x.sec, x.day, k.airline from x
      cross join lateral (select jsonb_object_keys(case when jsonb_typeof(p_new #> array[x.sec, x.day]) = 'object' then p_new #> array[x.sec, x.day] else '{}'::jsonb end)
                          union
                          select jsonb_object_keys(case when jsonb_typeof(p_old #> array[x.sec, x.day]) = 'object' then p_old #> array[x.sec, x.day] else '{}'::jsonb end)) as k(airline)
     where x.airline is null),
  money as (
    select e.path, e.sec, e.day, e.airline, p_old #> array[e.sec, e.day, e.airline] as had, p_new #> array[e.sec, e.day, e.airline] as got,
           cc.cash_at,
           case when e.sec = 'cash' then floor(cc.cash / 10000 + 0.5) / 100
                when cc.fixed_next7 > 0 then floor(cc.fixed_next7 / 10000 + 0.5) / 100 end as figure,
           (select max(ev.captured_at) from public.game_events ev
             where ev.airline_id = cc.airline_id and ev.debit > 0
               and ev.due_at > cc.cash_at and ev.due_at <= cc.cash_at + interval '7 days') as events_at
      from entries e
      left join public.airlines al on al.planner_name = e.airline and al.world_id = p_world_id
      left join public.capture_cash cc on cc.airline_id = al.id and cc.day = private.json_date(to_jsonb(e.day))),
  judged as (
    select m.*, coalesce(jsonb_typeof(m.got) = 'number' and m.figure is not null and (m.got #>> '{}')::numeric = m.figure
                         and (m.cash_at > to_timestamp(p_saved_at / 1000.0)
                              or (m.sec = 'fixed7' and m.events_at > to_timestamp(p_saved_at / 1000.0))), false) as late
      from money m)
  select d.path, d.kind, null::text from d where d.kind <> 'differs'
  union all
  select d.path,
         case when exists (select 1 from judged j where j.path = d.path) and not exists (select 1 from judged j where j.path = d.path and not j.late)
              then 'cash/fixed7 captured after the planner last saved' else 'differs' end,
         (select string_agg(format('%s %s %s (%s; %s)', j.sec, j.day, j.airline,
                   case when j.had is null then 'only in the tables' when j.got is null then 'only in planner_state' else 'the figure differs' end,
                   case when j.cash_at is null then 'no capture that date'
                        when j.figure is distinct from (case when jsonb_typeof(j.got) = 'number' then (j.got #>> '{}')::numeric end) then 'not the capture''s figure'
                        when j.cash_at > to_timestamp(p_saved_at / 1000.0) then 'captured after the planner last saved'
                        else 'captured before the planner last saved' end), ', ' order by j.sec, j.day, j.airline)
            from judged j where j.path = d.path and not j.late)
    from d where d.kind = 'differs'
$function$;

-- ============================================================ 3. the item engine (design §8, "Saving only what changed")
-- What a money-spent entry or a growth move says, as one text: they have no id, so identical entries are
-- interchangeable (design §8) and an entry is matched by what it says. The same text from the document and from a row.
create or replace function private.capex_key(p_airline text, p_day date, p_kind text, p_amount numeric, p_note text)
 returns text
 language sql
 immutable
 set search_path to ''
as $function$
  select jsonb_build_array(p_airline, p_day, p_kind, round(p_amount, 2), p_note)::text
$function$;

create or replace function private.growth_key(p_airline text, p_day date, p_move text, p_note text)
 returns text
 language sql
 immutable
 set search_path to ''
as $function$
  select jsonb_build_array(p_airline, p_day, p_move, p_note)::text
$function$;

-- A planner document as items, the unit a save changes and a clash is decided on (design §8's table): one per tail,
-- delivery, frequency, to-do and fare plan (by id); plan card, route edit, route cabin, interline, dismissed alert and
-- kept cabin (by key); route added (airline|hub|destination); monthly check (airline|task); cash and next-7-day figure
-- (date|airline); each ref list's entry (hubs by airline|code, types by name, configs and services by code) and each
-- key of ref's maps; money spent and growth moves by what they say and which of the identical ones they are (grp is
-- what they say). pos is the place in a list. A null value counts as no item.
create or replace function private.planner_items(p_doc jsonb)
 returns table (section text, key text, grp text, pos int, item jsonb)
 language sql
 immutable
 set search_path to ''
as $function$
  select s.section, x.k, x.k, x.pos, x.v
    from (values ('tails', 'id'), ('deliveries', 'reg'), ('freqs', 'id'), ('todos', 'id'), ('farePlan', 'id')) as s(section, id_key)
    cross join lateral (
      select distinct on (e.v ->> s.id_key) e.v ->> s.id_key as k, (e.ord - 1)::int as pos, e.v
        from jsonb_array_elements(case when jsonb_typeof(p_doc -> s.section) = 'array' then p_doc -> s.section else '[]'::jsonb end) with ordinality as e(v, ord)
       where jsonb_typeof(e.v) = 'object' and coalesce(e.v ->> s.id_key, '') <> ''
       order by e.v ->> s.id_key, e.ord) x
  union all
  select 'ref.' || s.sub, x.k, x.k, x.pos, x.v
    from (values ('hubs'), ('types'), ('configs'), ('services')) as s(sub)
    cross join lateral (
      select distinct on (kk.k) kk.k, (e.ord - 1)::int as pos, e.v
        from jsonb_array_elements(case when jsonb_typeof(p_doc #> array['ref', s.sub]) = 'array' then p_doc #> array['ref', s.sub] else '[]'::jsonb end) with ordinality as e(v, ord)
        cross join lateral (select case s.sub when 'hubs' then (e.v ->> 'airline') || '|' || (e.v ->> 'code')
                                              when 'types' then e.v ->> 'name' else e.v ->> 'code' end as k) kk
       where jsonb_typeof(e.v) = 'object' and coalesce(kk.k, '') <> ''
       order by kk.k, e.ord) x
  union all
  select 'routesAdded', x.k, x.k, x.pos, x.v
    from (select distinct on (kk.k) kk.k, (e.ord - 1)::int as pos, e.v
            from jsonb_array_elements(case when jsonb_typeof(p_doc -> 'routesAdded') = 'array' then p_doc -> 'routesAdded' else '[]'::jsonb end) with ordinality as e(v, ord)
            cross join lateral (select (e.v ->> 0) || '|' || (e.v ->> 1) || '|' || (e.v ->> 2) as k) kk
           where jsonb_typeof(e.v) = 'array' and kk.k is not null
           order by kk.k, e.ord) x
  union all
  select s.section, e.key, e.key, null::int, e.value
    from unnest(array['plans', 'routeEdits', 'routeCabin', 'interline', 'dismissed', 'cabinKeep']) as s(section)
    cross join lateral jsonb_each(case when jsonb_typeof(p_doc -> s.section) = 'object' then p_doc -> s.section else '{}'::jsonb end) e
   where e.value <> 'null'::jsonb
  union all
  select 'ref.' || s.sub, e.key, e.key, null::int, e.value
    from unnest(array['markets', 'curfews', 'utcOverrides', 'gameLinks', 'consts']) as s(sub)
    cross join lateral jsonb_each(case when jsonb_typeof(p_doc #> array['ref', s.sub]) = 'object' then p_doc #> array['ref', s.sub] else '{}'::jsonb end) e
   where e.value <> 'null'::jsonb
  union all
  select 'ref.timeMode', '', '', null::int, p_doc #> '{ref,timeMode}'
   where coalesce(p_doc #> '{ref,timeMode}', 'null'::jsonb) <> 'null'::jsonb
  union all
  select 'monthly', m.key || '|' || t.key, m.key || '|' || t.key, null::int, t.value
    from jsonb_each(case when jsonb_typeof(p_doc -> 'monthly') = 'object' then p_doc -> 'monthly' else '{}'::jsonb end) m
    cross join lateral jsonb_each(case when jsonb_typeof(m.value) = 'object' then m.value else '{}'::jsonb end) t
   where t.value <> 'null'::jsonb
  union all
  select s.section, d.key || '|' || a.key, d.key || '|' || a.key, null::int, a.value
    from unnest(array['cash', 'fixed7']) as s(section)
    cross join lateral jsonb_each(case when jsonb_typeof(p_doc -> s.section) = 'object' then p_doc -> s.section else '{}'::jsonb end) d
    cross join lateral jsonb_each(case when jsonb_typeof(d.value) = 'object' then d.value else '{}'::jsonb end) a
   where a.value <> 'null'::jsonb
  union all
  select x.section, x.content || '#' || row_number() over (partition by x.section, x.content order by x.pos), x.content, x.pos, x.v
    from (select 'capex' as section, (e.ord - 1)::int as pos, e.v,
                 case when private.json_date(e.v -> 'date') is not null and abs(private.json_num(e.v -> 'amountM')) < 1000000
                           and e.v ->> 'airline' is not null
                      then private.capex_key(e.v ->> 'airline', private.json_date(e.v -> 'date'),
                                             case when e.v ->> 'kind' in ('order', 'cabin', 'loss') then e.v ->> 'kind' else 'order' end,
                                             private.json_num(e.v -> 'amountM') * 1000000, e.v ->> 'note')
                      else 'unparsed ' || e.v::text end as content
            from jsonb_array_elements(case when jsonb_typeof(p_doc -> 'capex') = 'array' then p_doc -> 'capex' else '[]'::jsonb end) with ordinality as e(v, ord)
           where jsonb_typeof(e.v) = 'object'
          union all
          select 'growthLog', (e.ord - 1)::int, e.v,
                 case when private.json_date(e.v -> 'date') is not null and e.v ->> 'move' in ('big', 'freq', 'feeder') and e.v ->> 'airline' is not null
                      then private.growth_key(e.v ->> 'airline', private.json_date(e.v -> 'date'), e.v ->> 'move', e.v ->> 'note')
                      else 'unparsed ' || e.v::text end
            from jsonb_array_elements(case when jsonb_typeof(p_doc -> 'growthLog') = 'array' then p_doc -> 'growthLog' else '[]'::jsonb end) with ordinality as e(v, ord)
           where jsonb_typeof(e.v) = 'object') x
$function$;

-- The items someone else changed after a moment (design §8: "the log shows a later change by another actor or another
-- tab"): every change_log row of the world after p_since, except those this tab made (actor planner, detail p_client),
-- traced back to the items it belongs to. A row's identity comes from what the log says it was then and what it is
-- now, so a renamed, added or removed row counts under its old and new names. With no client, every later change counts.
create or replace function private.planner_touched(p_world_id bigint, p_since timestamptz, p_client text)
 returns table (section text, key text)
 language sql
 stable
 set search_path to ''
as $function$
  with ch as (
    select distinct l.table_name, l.row_key from public.change_log l
     where l.world_id = p_world_id and l.changed_at > p_since
       and not (p_client is not null and l.actor = 'planner' and l.actor_detail is not distinct from p_client)),
  -- what each of those rows was since then: the log's values (whole rows for an addition or a removal, the changed
  -- columns for a change), the row as it is now, and its key
  img as (
    select l.table_name, l.row_key, v.img
      from ch join public.change_log l on l.world_id = p_world_id and l.table_name = ch.table_name and l.row_key = ch.row_key and l.changed_at > p_since
      cross join lateral (values (l.old_values), (l.new_values)) as v(img)
     where v.img is not null
    union all select ch.table_name, ch.row_key, ch.row_key from ch
    union all select ch.table_name, ch.row_key, to_jsonb(t) from ch join public.aircraft t on ch.table_name = 'aircraft' and t.id = (ch.row_key ->> 'id')::bigint
    union all select ch.table_name, ch.row_key, to_jsonb(t) from ch join public.rotations t on ch.table_name = 'rotations' and t.id = (ch.row_key ->> 'id')::bigint
    union all select ch.table_name, ch.row_key, to_jsonb(t) from ch join public.flight_legs t on ch.table_name = 'flight_legs' and t.id = (ch.row_key ->> 'id')::bigint
    union all select ch.table_name, ch.row_key, to_jsonb(t) from ch join public.routes t on ch.table_name = 'routes' and t.id = (ch.row_key ->> 'id')::bigint
    union all select ch.table_name, ch.row_key, to_jsonb(t) from ch join public.plan_cards t on ch.table_name = 'plan_cards' and t.id = (ch.row_key ->> 'id')::bigint
    union all select ch.table_name, ch.row_key, to_jsonb(t) from ch join public.plan_card_legs t on ch.table_name = 'plan_card_legs' and t.id = (ch.row_key ->> 'id')::bigint
    union all select ch.table_name, ch.row_key, to_jsonb(t) from ch join public.todos t on ch.table_name = 'todos' and t.id = (ch.row_key ->> 'id')::bigint
    union all select ch.table_name, ch.row_key, to_jsonb(t) from ch join public.todo_items t on ch.table_name = 'todo_items' and t.id = (ch.row_key ->> 'id')::bigint
    union all select ch.table_name, ch.row_key, to_jsonb(t) from ch join public.fare_plan t on ch.table_name = 'fare_plan' and t.id = (ch.row_key ->> 'id')::bigint
    union all select ch.table_name, ch.row_key, to_jsonb(t) from ch join public.growth_log t on ch.table_name = 'growth_log' and t.id = (ch.row_key ->> 'id')::bigint
    union all select ch.table_name, ch.row_key, to_jsonb(t) from ch join public.spending_log t on ch.table_name = 'spending_log' and t.id = (ch.row_key ->> 'id')::bigint
    union all select ch.table_name, ch.row_key, to_jsonb(t) from ch join public.interline_agreements t on ch.table_name = 'interline_agreements' and t.id = (ch.row_key ->> 'id')::bigint
    union all select ch.table_name, ch.row_key, to_jsonb(t) from ch join public.monthly_checks t on ch.table_name = 'monthly_checks' and t.id = (ch.row_key ->> 'id')::bigint
    union all select ch.table_name, ch.row_key, to_jsonb(t) from ch join public.airline_bases t on ch.table_name = 'airline_bases' and t.id = (ch.row_key ->> 'id')::bigint
    union all select ch.table_name, ch.row_key, to_jsonb(t) from ch join public.aircraft_types t on ch.table_name = 'aircraft_types' and t.id = (ch.row_key ->> 'id')::bigint
    union all select ch.table_name, ch.row_key, to_jsonb(t) from ch join public.cabin_configs t on ch.table_name = 'cabin_configs' and t.id = (ch.row_key ->> 'id')::bigint
    union all select ch.table_name, ch.row_key, to_jsonb(t) from ch join public.service_profiles t on ch.table_name = 'service_profiles' and t.id = (ch.row_key ->> 'id')::bigint
    union all select ch.table_name, ch.row_key, to_jsonb(t) from ch join public.markets t on ch.table_name = 'markets' and t.id = (ch.row_key ->> 'id')::bigint
    union all select ch.table_name, ch.row_key, to_jsonb(t) from ch join public.settings t on ch.table_name = 'settings' and t.id = (ch.row_key ->> 'id')::bigint
    union all select ch.table_name, ch.row_key, to_jsonb(t) from ch join public.world_rules t on ch.table_name = 'world_rules' and t.id = (ch.row_key ->> 'id')::bigint
    union all select ch.table_name, ch.row_key, to_jsonb(t) from ch join public.airlines t on ch.table_name = 'airlines' and t.id = (ch.row_key ->> 'id')::bigint),
  names as (select a.id, a.planner_name from public.airlines a where a.world_id = p_world_id),
  -- a parent's identity, now or as the log had it since (it may have gone)
  parent as (
    select t.table_name, (t.row_key ->> 'id')::bigint as id, t.col, t.val from (
      select 'rotations' as table_name, jsonb_build_object('id', r.id) as row_key, 'legacy_key' as col, r.legacy_key as val from public.rotations r where r.world_id = p_world_id
      union all select 'todos', jsonb_build_object('id', r.id), 'legacy_key', r.legacy_key from public.todos r where r.world_id = p_world_id
      union all select 'aircraft', jsonb_build_object('id', r.id), 'registration', r.registration from public.aircraft r where r.world_id = p_world_id
      union all select 'plan_cards', jsonb_build_object('id', r.id), 'aircraft_id', r.aircraft_id::text from public.plan_cards r where r.world_id = p_world_id
      union all
      select l.table_name, l.row_key, c.col, coalesce(l.old_values, l.new_values) ->> c.col
        from public.change_log l
        join (values ('rotations', 'legacy_key'), ('todos', 'legacy_key'), ('aircraft', 'registration'), ('plan_cards', 'aircraft_id')) as c(tbl, col)
          on c.tbl = l.table_name
       where l.world_id = p_world_id and l.changed_at > p_since and coalesce(l.old_values, l.new_values) ? c.col) t
     where t.val is not null),
  regs as (select p.id, p.val as reg from parent p where p.table_name = 'aircraft')
  select x.section, x.key from (
    -- aircraft: its tail and its delivery; and its plan card when it was renamed
    select s.section, i.img ->> 'registration' as key from img i cross join unnest(array['tails', 'deliveries']) as s(section)
     where i.table_name = 'aircraft' and i.img ? 'registration'
    union all
    select 'plans', i.img ->> 'registration' from img i
     where i.table_name = 'aircraft' and i.img ? 'registration'
       and exists (select 1 from public.change_log l where l.world_id = p_world_id and l.table_name = 'aircraft' and l.row_key = i.row_key
                      and l.changed_at > p_since and l.op = 'update' and l.new_values ? 'registration')
    union all
    select 'freqs', i.img ->> 'legacy_key' from img i where i.table_name = 'rotations' and i.img ? 'legacy_key'
    union all
    select 'freqs', p.val from img i join parent p on p.table_name = 'rotations' and p.id = (i.img ->> 'rotation_id')::bigint
     where i.table_name = 'flight_legs' and i.img ? 'rotation_id'
    union all
    select s.section, n.planner_name || '|' || (i.img ->> 'hub_code') || '|' || (i.img ->> 'dest_code')
      from img i join names n on n.id = (i.img ->> 'airline_id')::bigint
      cross join unnest(array['routesAdded', 'routeEdits', 'routeCabin']) as s(section)
     where i.table_name = 'routes' and i.img ?& array['airline_id', 'hub_code', 'dest_code']
    union all
    select 'plans', r.reg from img i join regs r on r.id = (i.img ->> 'aircraft_id')::bigint
     where i.table_name = 'plan_cards' and i.img ? 'aircraft_id'
    union all
    select 'plans', r.reg from img i
      join parent p on p.table_name = 'plan_cards' and p.id = (i.img ->> 'plan_card_id')::bigint
      join regs r on r.id = p.val::bigint
     where i.table_name = 'plan_card_legs' and i.img ? 'plan_card_id'
    union all
    select 'todos', i.img ->> 'legacy_key' from img i where i.table_name = 'todos' and i.img ? 'legacy_key'
    union all
    select 'todos', p.val from img i join parent p on p.table_name = 'todos' and p.id = (i.img ->> 'todo_id')::bigint
     where i.table_name = 'todo_items' and i.img ? 'todo_id'
    union all
    select 'farePlan', i.img ->> 'legacy_key' from img i where i.table_name = 'fare_plan' and i.img ? 'legacy_key'
    union all
    select 'growthLog', private.growth_key(n.planner_name, (i.img ->> 'logged_on')::date, i.img ->> 'move', i.img ->> 'note')
      from img i join names n on n.id = (i.img ->> 'airline_id')::bigint
     where i.table_name = 'growth_log' and i.img ?& array['airline_id', 'logged_on', 'move']
    union all
    select 'capex', private.capex_key(n.planner_name, (i.img ->> 'spent_on')::date, i.img ->> 'kind', (i.img ->> 'amount')::numeric, i.img ->> 'note')
      from img i join names n on n.id = (i.img ->> 'airline_id')::bigint
     where i.table_name = 'spending_log' and i.img ?& array['airline_id', 'spent_on', 'kind', 'amount']
    union all
    select 'interline', n.planner_name || '|' || (i.img ->> 'country_code')
      from img i join names n on n.id = (i.img ->> 'airline_id')::bigint
     where i.table_name = 'interline_agreements' and i.img ?& array['airline_id', 'country_code']
    union all
    select 'monthly', coalesce(n.planner_name, 'Equinox') || '|' || (i.img ->> 'task')
      from img i left join names n on n.id = (i.img ->> 'airline_id')::bigint
     where i.table_name = 'monthly_checks' and i.img ?& array['airline_id', 'task']
    union all
    select 'dismissed', i.img ->> 'alert_key' from img i where i.table_name = 'dismissals' and i.img ? 'alert_key'
    union all
    select 'cabinKeep', r.reg || '|' || (i.img ->> 'cabin') from img i join regs r on r.id = (i.img ->> 'aircraft_id')::bigint
     where i.table_name = 'aircraft_cabin_keeps' and i.img ?& array['aircraft_id', 'cabin']
    union all
    select s.section, (i.img ->> 'day') || '|' || n.planner_name
      from img i join names n on n.id = (i.img ->> 'airline_id')::bigint cross join unnest(array['cash', 'fixed7']) as s(section)
     where i.table_name = 'cash_entries' and i.img ?& array['airline_id', 'day']
    union all
    select 'ref.hubs', n.planner_name || '|' || (i.img ->> 'airport_code')
      from img i join names n on n.id = (i.img ->> 'airline_id')::bigint
     where i.table_name = 'airline_bases' and i.img ?& array['airline_id', 'airport_code']
    union all
    select s.section, i.img ->> 'airport_code' from img i cross join unnest(array['ref.curfews', 'ref.utcOverrides']) as s(section)
     where i.table_name = 'world_airports' and i.img ? 'airport_code'
    union all
    select 'ref.hubs', n.planner_name || '|' || b.airport_code
      from img i join public.airline_bases b on b.world_id = p_world_id and b.airport_code = i.img ->> 'airport_code'
      join names n on n.id = b.airline_id
     where i.table_name = 'world_airports'
    union all
    select 'ref.types', i.img ->> 'name' from img i where i.table_name = 'aircraft_types' and i.img ? 'name'
    union all
    select 'ref.configs', i.img ->> 'code' from img i where i.table_name = 'cabin_configs' and i.img ? 'code'
    union all
    select 'ref.services', i.img ->> 'code' from img i where i.table_name = 'service_profiles' and i.img ? 'code'
    union all
    select 'ref.markets', n.planner_name || '|' || (i.img ->> 'name')
      from img i join names n on n.id = (i.img ->> 'airline_id')::bigint
     where i.table_name = 'markets' and i.img ?& array['airline_id', 'name']
    union all
    select case when i.img ->> 'key' = 'planner_time_mode' then 'ref.timeMode' else 'ref.consts' end, m.k
      from img i join (values ('buf', 'bank_buffer_min'), ('ovh', 'block_allowance_min'), ('arrwin', 'bank_arrival_window_min'),
                              ('depwin', 'bank_departure_window_min'), ('maxWait', 'connection_max_wait_h'), ('legalGap', 'legal_gap_h'),
                              ('turnMargin', 'turn_margin_min'), ('maintMinGround', 'maint_min_ground_min'),
                              ('leeway', 'load_leeway_days'), ('lfWindow', 'load_window_days'), ('', 'planner_time_mode')) as m(k, setting)
        on m.setting = i.img ->> 'key'
     where i.table_name = 'settings' and i.img ? 'key' and i.img -> 'airline_id' = 'null'::jsonb
    union all
    select 'ref.consts', 'depCap' from img i where i.table_name = 'world_rules' and i.img ->> 'key' = 'departures_per_airport_week'
    union all
    select 'ref.gameLinks', i.img ->> 'planner_name' from img i where i.table_name = 'airlines' and i.img ? 'planner_name'
  ) x
   where x.key is not null
$function$;

-- ---------- the writers. Each reads pg_temp.t_pa, which private.planner_apply() fills: one row per item of the saved
-- document or of the tables, with its state (same; changed; skipped, when someone else changed it after the tab's base)
-- and its effective value (eff_item: the document's unless skipped). Each writes only the rows of changed items, with
-- the loader's own rules (migration 20261010120000), and returns how many rows it wrote.

-- Airports and countries the changed items name, by their code only, so nothing that names them is refused (as the
-- loader does)
create or replace function private.planner_apply_places(p_world_id bigint)
 returns jsonb
 language plpgsql
 set search_path to ''
as $function$
declare n int; m int;
begin
  insert into public.airports (code)
  select distinct x.code from (
    select p.new_item ->> 'base' as code from pg_temp.t_pa p where p.section in ('tails', 'deliveries', 'plans') and p.state = 'changed'
    union all select p.new_item ->> i from pg_temp.t_pa p, generate_series(1, 2) i where p.section = 'routesAdded' and p.state = 'changed'
    union all select split_part(p.key, '|', i) from pg_temp.t_pa p, generate_series(2, 3) i
               where p.section in ('routesAdded', 'routeEdits', 'routeCabin') and p.state = 'changed'
    union all select split_part(p.new_item ->> 'routeKey', '|', i) from pg_temp.t_pa p, generate_series(2, 3) i
               where p.section in ('freqs', 'farePlan') and p.state = 'changed'
    union all select l ->> k from pg_temp.t_pa p
                cross join lateral jsonb_array_elements(case when jsonb_typeof(p.new_item -> 'legs') = 'array' then p.new_item -> 'legs' else '[]'::jsonb end) l
                cross join unnest(array['from', 'to']) k
               where p.section = 'plans' and p.state = 'changed'
    union all select p.new_item ->> 'code' from pg_temp.t_pa p where p.section = 'ref.hubs' and p.state = 'changed'
    union all select p.key from pg_temp.t_pa p where p.section in ('ref.curfews', 'ref.utcOverrides') and p.state = 'changed' and p.new_item is not null
  ) x
   where x.code ~ '^[A-Z0-9]{3,4}$'
  on conflict (code) do nothing;
  get diagnostics n = row_count;
  insert into public.countries (code, name)
  select distinct substr(p.key, strpos(p.key, '|') + 1), substr(p.key, strpos(p.key, '|') + 1)
    from pg_temp.t_pa p
   where p.section = 'interline' and p.state = 'changed' and p.new_item is not null and strpos(p.key, '|') > 0
     and substr(p.key, strpos(p.key, '|') + 1) <> ''
  on conflict (code) do nothing;
  get diagnostics m = row_count;
  return jsonb_build_object('airports', n, 'countries', m);
end
$function$;

-- ref: types, cabin layouts, services, markets, the planner's constants, time mode, hubs and focus cities, and what the
-- world says about their airports (connection times, night bans, offsets). A type, layout or service renamed in place
-- (the item gone and a new one at the same place) keeps its row.
create or replace function private.planner_apply_reference(p_world_id bigint)
 returns jsonb
 language plpgsql
 set search_path to ''
as $function$
declare w bigint := p_world_id; n int; v_out jsonb := '{}'::jsonb; v_mct jsonb;
begin
  if not exists (select 1 from pg_temp.t_pa where section like 'ref.%' and state = 'changed') then return v_out; end if;

  -- renamed in place
  update public.aircraft_types t set name = a.key
    from pg_temp.t_pa r join pg_temp.t_pa a on a.section = r.section and a.new_pos = r.cur_pos and a.state = 'changed' and a.cur_item is null
   where r.section = 'ref.types' and r.state = 'changed' and r.new_item is null and t.world_id = w and t.name = r.key
     and not exists (select 1 from public.aircraft_types x where x.world_id = w and x.name = a.key);
  update public.cabin_configs t set code = a.key
    from pg_temp.t_pa r join pg_temp.t_pa a on a.section = r.section and a.new_pos = r.cur_pos and a.state = 'changed' and a.cur_item is null
   where r.section = 'ref.configs' and r.state = 'changed' and r.new_item is null and t.world_id = w and t.code = r.key
     and not exists (select 1 from public.cabin_configs x where x.world_id = w and x.code = a.key);
  update public.service_profiles t set code = a.key
    from pg_temp.t_pa r join pg_temp.t_pa a on a.section = r.section and a.new_pos = r.cur_pos and a.state = 'changed' and a.cur_item is null
   where r.section = 'ref.services' and r.state = 'changed' and r.new_item is null and t.world_id = w and t.code = r.key
     and not exists (select 1 from public.service_profiles x where x.world_id = w and x.code = a.key);

  -- aircraft types (ref.types)
  insert into public.aircraft_types as x (world_id, name, family_no, seats_max, cruise_kmh, min_turn_min, gap_target_h,
                                          maint_per_hour, maint_per_cycle, ground_keep_min, price)
  select w, p.key, private.json_int(t -> 'family'), private.json_int(t -> 'seats'), private.json_int(t -> 'cruise'),
         (select v::smallint from private.json_int(t -> 'minTurn') v where abs(v) < 32000),
         (select v from private.json_num(t -> 'gap') v where abs(v) < 1000),
         (select v from private.json_num(t -> 'mHour') v where abs(v) < 1000),
         (select v from private.json_num(t -> 'mCycle') v where abs(v) < 1000),
         (select v::smallint from private.json_int(t -> 'greens') v where abs(v) < 32000),
         (select v * 1000000 from private.json_num(t -> 'priceM') v where abs(v) < 1000000)
    from pg_temp.t_pa p cross join lateral (select p.new_item as t) i
   where p.section = 'ref.types' and p.state = 'changed' and p.new_item is not null
   order by p.new_pos
  on conflict (world_id, name) do update set family_no = excluded.family_no, seats_max = excluded.seats_max,
    cruise_kmh = excluded.cruise_kmh, min_turn_min = excluded.min_turn_min, gap_target_h = excluded.gap_target_h,
    maint_per_hour = excluded.maint_per_hour, maint_per_cycle = excluded.maint_per_cycle,
    ground_keep_min = excluded.ground_keep_min, price = excluded.price
  where (x.family_no, x.seats_max, x.cruise_kmh, x.min_turn_min, x.gap_target_h, x.maint_per_hour, x.maint_per_cycle,
         x.ground_keep_min, x.price)
        is distinct from (excluded.family_no, excluded.seats_max, excluded.cruise_kmh, excluded.min_turn_min,
                          excluded.gap_target_h, excluded.maint_per_hour, excluded.maint_per_cycle,
                          excluded.ground_keep_min, excluded.price);
  get diagnostics n = row_count; v_out := v_out || jsonb_build_object('aircraft_types', n);

  -- cabin layouts (ref.configs)
  insert into public.cabin_configs as x (world_id, code, aircraft_type_id, cabin, seats, business_seats, economy_seats, cost, note)
  select w, p.key, (select ty.id from public.aircraft_types ty where ty.world_id = w and ty.name = t ->> 'type'),
         case when t ->> 'cabin' in ('Standard', 'Leisure', 'Leisure Plus', 'Comfort') then t ->> 'cabin' end,
         private.json_int(t -> 'seats'), private.json_int(t -> 'c'), private.json_int(t -> 'y'),
         (select v * 1000000 from private.json_num(t -> 'costM') v where abs(v) < 1000000), t ->> 'note'
    from pg_temp.t_pa p cross join lateral (select p.new_item as t) i
   where p.section = 'ref.configs' and p.state = 'changed' and p.new_item is not null
   order by p.new_pos
  on conflict (world_id, code) do update set aircraft_type_id = excluded.aircraft_type_id, cabin = excluded.cabin,
    seats = excluded.seats, business_seats = excluded.business_seats, economy_seats = excluded.economy_seats,
    cost = excluded.cost, note = excluded.note
  where (x.aircraft_type_id, x.cabin, x.seats, x.business_seats, x.economy_seats, x.cost, x.note)
        is distinct from (excluded.aircraft_type_id, excluded.cabin, excluded.seats, excluded.business_seats,
                          excluded.economy_seats, excluded.cost, excluded.note);
  get diagnostics n = row_count; v_out := v_out || jsonb_build_object('cabin_configs', n);

  -- on-board service (ref.services): "Legacy" means every airline without its own
  insert into public.service_profiles as x (world_id, airline_id, code, up_to_km, note)
  select w, (select al.id from public.airlines al where al.world_id = w and al.planner_name = t ->> 'airline'),
         p.key, private.json_int(t -> 'upTo'), t ->> 'note'
    from pg_temp.t_pa p cross join lateral (select p.new_item as t) i
   where p.section = 'ref.services' and p.state = 'changed' and p.new_item is not null
   order by p.new_pos
  on conflict (world_id, code) do update set airline_id = excluded.airline_id, up_to_km = excluded.up_to_km, note = excluded.note
  where (x.airline_id, x.up_to_km, x.note) is distinct from (excluded.airline_id, excluded.up_to_km, excluded.note);
  get diagnostics n = row_count; v_out := v_out || jsonb_build_object('service_profiles', n);

  -- markets (ref.markets, keyed "Airline|Market")
  insert into public.markets as x (world_id, airline_id, name, default_type_id, default_config_id, fare_y_pct, fare_j_pct)
  select w, al.id, substr(p.key, strpos(p.key, '|') + 1),
         (select ty.id from public.aircraft_types ty where ty.world_id = w and ty.name = p.new_item ->> 'aircraft'),
         (select cc.id from public.cabin_configs cc where cc.world_id = w and cc.code = p.new_item ->> 'config'),
         (select v from private.json_num(p.new_item -> 'priceY') v where abs(v) < 10000),
         (select v from private.json_num(p.new_item -> 'priceJ') v where abs(v) < 10000)
    from pg_temp.t_pa p join public.airlines al on al.world_id = w and al.planner_name = split_part(p.key, '|', 1)
   where p.section = 'ref.markets' and p.state = 'changed' and jsonb_typeof(p.new_item) = 'object' and strpos(p.key, '|') > 0
  on conflict (airline_id, name) do update set default_type_id = excluded.default_type_id,
    default_config_id = excluded.default_config_id, fare_y_pct = excluded.fare_y_pct, fare_j_pct = excluded.fare_j_pct
  where (x.default_type_id, x.default_config_id, x.fare_y_pct, x.fare_j_pct)
        is distinct from (excluded.default_type_id, excluded.default_config_id, excluded.fare_y_pct, excluded.fare_j_pct);
  get diagnostics n = row_count; v_out := v_out || jsonb_build_object('markets', n);

  -- the planner's constants (ref.consts) as settings, at the loader's default when the planner leaves one out; depCap is
  -- the house rule's figure; and the time mode (ref.timeMode)
  with m(k, setting, dflt) as (values ('buf', 'bank_buffer_min', '0'::jsonb), ('ovh', 'block_allowance_min', '25'),
         ('arrwin', 'bank_arrival_window_min', '60'), ('depwin', 'bank_departure_window_min', '60'),
         ('maxWait', 'connection_max_wait_h', '8'), ('legalGap', 'legal_gap_h', '2'), ('turnMargin', 'turn_margin_min', '10'),
         ('maintMinGround', 'maint_min_ground_min', '120'), ('leeway', 'load_leeway_days', '7'), ('lfWindow', 'load_window_days', '14'))
  update public.settings s set value = coalesce(p.new_item, m.dflt)
    from pg_temp.t_pa p join m on m.k = p.key
   where p.section = 'ref.consts' and p.state = 'changed' and s.world_id = w and s.airline_id is null and s.key = m.setting
     and s.value is distinct from coalesce(p.new_item, m.dflt);
  get diagnostics n = row_count; v_out := v_out || jsonb_build_object('settings', n);
  update public.world_rules r set value = jsonb_set(r.value, '{value}', coalesce(p.new_item, '5000'::jsonb))
    from pg_temp.t_pa p
   where p.section = 'ref.consts' and p.key = 'depCap' and p.state = 'changed' and r.world_id = w
     and r.key = 'departures_per_airport_week' and jsonb_typeof(r.value) = 'object'
     and r.value -> 'value' is distinct from coalesce(p.new_item, '5000'::jsonb);
  get diagnostics n = row_count; v_out := v_out || jsonb_build_object('world_rules', n);
  update public.settings s set value = coalesce(p.new_item, '"local"'::jsonb)
    from pg_temp.t_pa p
   where p.section = 'ref.timeMode' and p.state = 'changed' and s.world_id = w and s.airline_id is null
     and s.key = 'planner_time_mode' and s.value is distinct from coalesce(p.new_item, '"local"'::jsonb);

  -- hubs and focus cities (ref.hubs): gone ones first (nothing may point at them), then the rest in the planner's order;
  -- the main hubs as the planner's MAIN_HUB has them (the loader's list)
  if exists (select 1 from pg_temp.t_pa where section = 'ref.hubs' and state = 'changed') then
    update public.airline_bases x set parent_base_id = null
     where x.world_id = w and x.parent_base_id in (
       select b.id from pg_temp.t_pa p
         join public.airlines al on al.world_id = w and al.planner_name = p.cur_item ->> 'airline'
         join public.airline_bases b on b.airline_id = al.id and b.airport_code = p.cur_item ->> 'code'
        where p.section = 'ref.hubs' and p.state = 'changed' and p.new_item is null);
    delete from public.airline_bases b
     using pg_temp.t_pa p, public.airlines al
     where p.section = 'ref.hubs' and p.state = 'changed' and p.new_item is null
       and al.world_id = w and al.planner_name = p.cur_item ->> 'airline' and b.airline_id = al.id and b.airport_code = p.cur_item ->> 'code';
    get diagnostics n = row_count; v_out := v_out || jsonb_build_object('airline_bases removed', n);
    with main(planner_name, code) as (values ('Pan American', 'JFK'), ('Kingfisher', 'DEL'), ('Virgin Atlantic', 'LGW'),
                                             ('China Eastern', 'PVG'), ('Malaysia Airlines', 'KUL'))
    insert into public.airline_bases as x (world_id, airline_id, airport_code, role, is_main, bank_times, flight_no_from,
                                           last_flight_no, hold_note, position)
    select w, al.id, h ->> 'code', case when h ->> 'role' = 'focus' then 'focus' else 'hub' end,
           exists (select 1 from main where main.planner_name = al.planner_name and main.code = h ->> 'code'),
           case when jsonb_typeof(h -> 'banks') = 'array' and jsonb_array_length(h -> 'banks') <= 4 then
             array(select case when private.clock_min(b.v #>> '{}') is not null
                               then make_time(private.clock_min(b.v #>> '{}') / 60, private.clock_min(b.v #>> '{}') % 60, 0) end
                     from jsonb_array_elements(h -> 'banks') with ordinality as b(v, o) order by b.o) end,
           (select v::int from private.json_int(h -> 'block') v where abs(v) < 2000000000),
           (select v::int from private.json_int(h -> 'lastUsed') v where abs(v) < 2000000000),
           h ->> 'hold', p.new_pos
      from pg_temp.t_pa p cross join lateral (select p.new_item as h) i
      join public.airlines al on al.world_id = w and al.planner_name = h ->> 'airline'
     where p.section = 'ref.hubs' and p.state = 'changed' and p.new_item is not null
       and exists (select 1 from public.airports a where a.code = h ->> 'code')
     order by p.new_pos
    on conflict (airline_id, airport_code) do update set role = excluded.role, is_main = excluded.is_main,
      bank_times = excluded.bank_times, flight_no_from = excluded.flight_no_from, last_flight_no = excluded.last_flight_no,
      hold_note = excluded.hold_note, position = excluded.position
    where (x.role, x.is_main, x.bank_times, x.flight_no_from, x.last_flight_no, x.hold_note, x.position)
          is distinct from (excluded.role, excluded.is_main, excluded.bank_times, excluded.flight_no_from,
                            excluded.last_flight_no, excluded.hold_note, excluded.position);
    get diagnostics n = row_count; v_out := v_out || jsonb_build_object('airline_bases', n);
    -- the others keep their place in the list
    update public.airline_bases b set position = p.new_pos
      from pg_temp.t_pa p join public.airlines al on al.world_id = w and al.planner_name = p.new_item ->> 'airline'
     where p.section = 'ref.hubs' and p.state = 'same' and b.airline_id = al.id and b.airport_code = p.new_item ->> 'code'
       and b.position is distinct from p.new_pos;
    -- a focus city's hub: the airline's own base at that airport, else any base there
    update public.airline_bases b set parent_base_id = x.parent_id
      from (select b2.id, (select q.id from public.airline_bases q
                            where q.world_id = w and q.airport_code = p.eff_item ->> 'parent' and q.id <> b2.id
                            order by (q.airline_id = b2.airline_id) desc, q.id limit 1) as parent_id
              from pg_temp.t_pa p
              join public.airlines al on al.world_id = w and al.planner_name = p.eff_item ->> 'airline'
              join public.airline_bases b2 on b2.airline_id = al.id and b2.airport_code = p.eff_item ->> 'code'
             where p.section = 'ref.hubs' and p.eff_item is not null) x
     where b.id = x.id and b.parent_base_id is distinct from x.parent_id;
  end if;

  -- what the world says about the airports the changed hubs, night bans and offsets name: a hub's own connection time
  -- (the first in the list) else site_content.mct, the night ban, the offset correction (as the loader works them out)
  if exists (select 1 from pg_temp.t_pa where section in ('ref.hubs', 'ref.curfews', 'ref.utcOverrides') and state = 'changed') then
    select s.value into v_mct from public.site_content s where s.key = 'mct';
    v_mct := case when jsonb_typeof(v_mct) = 'object' then v_mct else '{}'::jsonb end;
    if to_regclass('pg_temp.t_pa_codes') is null then
      create temporary table t_pa_codes (code text primary key, mct_min smallint, ban_from time, ban_to time, off numeric) on commit drop;
    end if;
    truncate pg_temp.t_pa_codes;
    with codes as (
      select coalesce(p.new_item, p.cur_item) ->> 'code' as code from pg_temp.t_pa p where p.section = 'ref.hubs' and p.state = 'changed'
      union select p.key from pg_temp.t_pa p where p.section in ('ref.curfews', 'ref.utcOverrides') and p.state = 'changed'),
    hub_mct as (
      select distinct on (p.eff_item ->> 'code') p.eff_item ->> 'code' as code, private.json_num(p.eff_item -> 'mct') * 60 as m
        from pg_temp.t_pa p
       where p.section = 'ref.hubs' and p.eff_item is not null and private.json_num(p.eff_item -> 'mct') is not null
       order by p.eff_item ->> 'code', coalesce(p.new_pos, p.cur_pos)),
    ban as (select p.key as code, regexp_match(p.eff_item #>> '{}', '^(\d{1,2}:\d{2})-(\d{1,2}:\d{2})$') as m
              from pg_temp.t_pa p where p.section = 'ref.curfews' and p.eff_item is not null),
    ovr as (select p.key as code, private.json_num(p.eff_item) as off
              from pg_temp.t_pa p where p.section = 'ref.utcOverrides' and p.eff_item is not null)
    insert into pg_temp.t_pa_codes
    select c.code,
           (select case when x.m = round(x.m) and abs(x.m) < 32000 then x.m::smallint end
              from (select coalesce(hm.m, private.json_num(v_mct -> c.code)) as m) x),
           case when private.clock_min(b.m[1]) is not null then make_time(private.clock_min(b.m[1]) / 60, private.clock_min(b.m[1]) % 60, 0) end,
           case when private.clock_min(b.m[2]) is not null then make_time(private.clock_min(b.m[2]) / 60, private.clock_min(b.m[2]) % 60, 0) end,
           case when abs(o.off) <= 14 then round(o.off, 2) end
      from codes c
      left join hub_mct hm on hm.code = c.code
      left join ban b on b.code = c.code
      left join ovr o on o.code = c.code
     where c.code is not null and exists (select 1 from public.airports a where a.code = c.code);
    insert into public.world_airports as x (world_id, airport_code, mct_min, night_ban_from, night_ban_to, utc_offset_override)
    select w, c.code, c.mct_min, c.ban_from, c.ban_to, c.off from pg_temp.t_pa_codes c
     where c.mct_min is not null or c.ban_from is not null or c.ban_to is not null or c.off is not null
        or exists (select 1 from public.world_airports y where y.world_id = w and y.airport_code = c.code)
    on conflict (world_id, airport_code) do update set mct_min = excluded.mct_min, night_ban_from = excluded.night_ban_from,
      night_ban_to = excluded.night_ban_to, utc_offset_override = excluded.utc_offset_override
    where (x.mct_min, x.night_ban_from, x.night_ban_to, x.utc_offset_override)
          is distinct from (excluded.mct_min, excluded.night_ban_from, excluded.night_ban_to, excluded.utc_offset_override);
    get diagnostics n = row_count; v_out := v_out || jsonb_build_object('world_airports', n);
    -- a row nothing describes any more goes (the loader's tidy-up)
    delete from public.world_airports x using pg_temp.t_pa_codes c
     where x.world_id = w and x.airport_code = c.code
       and x.mct_min is null and x.night_ban_from is null and x.night_ban_to is null and x.utc_offset_override is null
       and x.game_airport_id is null and not x.closed and x.note is null and not (v_mct ? c.code)
       and not exists (select 1 from public.airline_bases b where b.world_id = w and b.airport_code = c.code);
  end if;
  return v_out;
end
$function$;

-- Routes: what the planner added, edited or chose a cabin for (routesAdded, routeEdits, routeCabin), and any route a
-- changed frequency or fare plan names. A route added in the planner takes its figures from routesAdded; otherwise a
-- research route keeps its own, and one that stops being added takes the research's again (planner_data). Routes
-- nothing names any more are removed in private.planner_apply_tidy(), once frequencies and fare plans are written.
create or replace function private.planner_apply_routes(p_world_id bigint)
 returns jsonb
 language plpgsql
 set search_path to ''
as $function$
declare w bigint := p_world_id; n int;
begin
  if to_regclass('pg_temp.t_pa_routes') is null then
    create temporary table t_pa_routes (key text primary key, airline_id bigint, hub text, dest text, added jsonb, ord int,
      edit jsonb, cabin jsonb, named boolean, research jsonb, checked boolean not null default false) on commit drop;
  end if;
  truncate pg_temp.t_pa_routes;
  if not exists (select 1 from pg_temp.t_pa where state = 'changed'
                    and section in ('routesAdded', 'routeEdits', 'routeCabin', 'freqs', 'farePlan')) then
    return '{}'::jsonb;
  end if;
  insert into pg_temp.t_pa_routes (key, airline_id, hub, dest, added, ord, edit, cabin, named)
  select k.key, al.id, split_part(k.key, '|', 2), split_part(k.key, '|', 3),
         (select p.eff_item from pg_temp.t_pa p where p.section = 'routesAdded' and p.key = k.key and jsonb_typeof(p.eff_item) = 'array'),
         (select coalesce(p.new_pos, p.cur_pos) from pg_temp.t_pa p where p.section = 'routesAdded' and p.key = k.key),
         (select p.eff_item from pg_temp.t_pa p where p.section = 'routeEdits' and p.key = k.key and jsonb_typeof(p.eff_item) = 'object'),
         (select p.eff_item from pg_temp.t_pa p where p.section = 'routeCabin' and p.key = k.key),
         exists (select 1 from pg_temp.t_pa p where p.section in ('freqs', 'farePlan') and p.eff_item ->> 'routeKey' = k.key)
    from (select p.key from pg_temp.t_pa p where p.section in ('routesAdded', 'routeEdits', 'routeCabin') and p.state = 'changed'
          union
          select p.new_item ->> 'routeKey' from pg_temp.t_pa p
           where p.section in ('freqs', 'farePlan') and p.state = 'changed' and p.new_item ->> 'routeKey' is not null) k
    join public.airlines al on al.world_id = w and al.planner_name = split_part(k.key, '|', 1)
   where split_part(k.key, '|', 4) = ''
     and exists (select 1 from public.airports a where a.code = split_part(k.key, '|', 2))
     and exists (select 1 from public.airports a where a.code = split_part(k.key, '|', 3));

  -- the research's own entry, where it may be needed: a route that isn't added and isn't a research row yet, or was
  -- added until now, or that nothing names any more (to know whether it stays as a research route)
  update pg_temp.t_pa_routes r set checked = true
   where r.added is null
     and (not exists (select 1 from public.routes o where o.airline_id = r.airline_id and o.hub_code = r.hub and o.dest_code = r.dest and o.source = 'research')
          or (r.edit is null and r.cabin is null and not r.named));
  if exists (select 1 from pg_temp.t_pa_routes where checked) then
    update pg_temp.t_pa_routes r set research = x.v
      from (select distinct on (k.k) k.k, e.v
              from jsonb_array_elements((select case when jsonb_typeof(d.value -> 'routes') = 'array' then d.value -> 'routes' else '[]'::jsonb end
                                           from public.planner_data d where d.key = 'DATA')) with ordinality as e(v, ord)
              cross join lateral (select (e.v ->> 0) || '|' || (e.v ->> 1) || '|' || (e.v ->> 2) as k) k
             where jsonb_typeof(e.v) = 'array' and k.k in (select key from pg_temp.t_pa_routes where checked)
             order by k.k, e.ord) x
     where r.key = x.k;
  end if;

  insert into public.routes as x (world_id, airline_id, hub_code, dest_code, city, country_label, distance_km, market_id, stars,
                                  source, removed, removed_note, city_override, distance_override_km, market_override_id,
                                  stars_override, cabin_choice)
  select w, r.airline_id, r.hub, r.dest,
         case when s.keep then old.city else s.src ->> 3 end,
         case when s.keep then old.country_label else s.src ->> 4 end,
         case when s.keep then old.distance_km else (select v::int from private.json_int(s.src -> 5) v where abs(v) < 2000000000) end,
         case when s.keep then old.market_id else (select m.id from public.markets m where m.airline_id = r.airline_id and m.name = s.src ->> 6) end,
         case when s.keep then old.stars else (select v::smallint from private.json_int(s.src -> 7) v where abs(v) < 32000) end,
         case when r.added is not null then 'added' else 'research' end,
         coalesce(r.edit -> 'removed' = 'true'::jsonb, false), r.edit ->> 'note', r.edit ->> 'city',
         (select v::int from private.json_int(r.edit -> 'dist') v where abs(v) < 2000000000),
         (select m.id from public.markets m where m.airline_id = r.airline_id and m.name = r.edit ->> 'market'),
         (select v::smallint from private.json_int(r.edit -> 'stars') v where abs(v) < 32000),
         case when r.cabin #>> '{}' in ('Standard', 'Leisure', 'Leisure Plus', 'Comfort') then r.cabin #>> '{}' end
    from pg_temp.t_pa_routes r
    left join public.routes old on old.airline_id = r.airline_id and old.hub_code = r.hub and old.dest_code = r.dest
    cross join lateral (select case when r.added is not null then r.added when old.id is null or old.source = 'added' then r.research end as src,
                               (r.added is null and old.id is not null and old.source = 'research') as keep) s
   where old.id is not null or r.added is not null or r.edit is not null or r.cabin is not null or r.research is not null or r.named
   order by r.added is null, r.ord, r.key   -- routes added in the planner in its order: the getter lists them by id
  on conflict (airline_id, hub_code, dest_code) do update set city = excluded.city, country_label = excluded.country_label,
    distance_km = excluded.distance_km, market_id = excluded.market_id, stars = excluded.stars, source = excluded.source,
    removed = excluded.removed, removed_note = excluded.removed_note, city_override = excluded.city_override,
    distance_override_km = excluded.distance_override_km, market_override_id = excluded.market_override_id,
    stars_override = excluded.stars_override, cabin_choice = excluded.cabin_choice
  where (x.city, x.country_label, x.distance_km, x.market_id, x.stars, x.source, x.removed, x.removed_note, x.city_override,
         x.distance_override_km, x.market_override_id, x.stars_override, x.cabin_choice)
        is distinct from (excluded.city, excluded.country_label, excluded.distance_km, excluded.market_id, excluded.stars,
                          excluded.source, excluded.removed, excluded.removed_note, excluded.city_override,
                          excluded.distance_override_km, excluded.market_override_id, excluded.stars_override,
                          excluded.cabin_choice);
  get diagnostics n = row_count;
  return jsonb_build_object('routes', n);
end
$function$;

-- Aircraft: one row per registration from its tail and its delivery (today's type, cabin and base from the tail, as
-- ordered from the delivery), with each list's place kept in extra (tails_index, deliveries_index) and kept in step
-- with the document's order. Aircraft in neither list any more are handled in private.planner_apply_tidy().
create or replace function private.planner_apply_fleet(p_world_id bigint)
 returns jsonb
 language plpgsql
 set search_path to ''
as $function$
declare w bigint := p_world_id; n int; v_out jsonb := '{}'::jsonb;
  k_tail text[] := array['id', 'airline', 'base', 'type', 'config', 'status', 'maint', 'checkedOn', 'schedChangedOn'];
  k_delivery text[] := array['reg', 'airline', 'utc', 'date', 'base', 'type', 'config', 'plan'];
begin
  if not exists (select 1 from pg_temp.t_pa where section in ('tails', 'deliveries') and state = 'changed') then return v_out; end if;
  with regs as (select distinct p.key as reg from pg_temp.t_pa p where p.section in ('tails', 'deliveries') and p.state = 'changed'),
  m as (
    select r.reg, t.eff_item as tv, d.eff_item as dv,
           case when t.state <> 'skipped' then t.new_pos end as ti,
           case when d.state <> 'skipped' then d.new_pos end as di,
           (select al.id from public.airlines al where al.world_id = w and al.planner_name = coalesce(t.eff_item ->> 'airline', d.eff_item ->> 'airline')) as airline_id,
           private.json_ts(d.eff_item -> 'utc') as delivery_at
      from regs r
      left join pg_temp.t_pa t on t.section = 'tails' and t.key = r.reg
      left join pg_temp.t_pa d on d.section = 'deliveries' and d.key = r.reg),
  src as (
    select m.*, old.extra as old_extra,
           (select ty.id from public.aircraft_types ty where ty.world_id = w and ty.name = coalesce(nullif(m.tv ->> 'type', ''), m.dv ->> 'type')) as type_id,
           (select cc.id from public.cabin_configs cc where cc.world_id = w and cc.code = m.tv ->> 'config') as config_id,
           (select a.code from public.airports a where a.code = case when m.tv is not null then m.tv ->> 'base' else m.dv ->> 'base' end) as base,
           (select cc.id from public.cabin_configs cc where cc.world_id = w and cc.code = m.dv ->> 'config') as order_config_id,
           (select a.code from public.airports a where a.code = m.dv ->> 'base') as order_base
      from m left join public.aircraft old on old.world_id = w and old.registration = m.reg
     where m.airline_id is not null and (m.tv is not null or m.dv is not null))
  insert into public.aircraft as x (world_id, airline_id, registration, aircraft_type_id, cabin_config_id, base_code, status,
                                    ordered_on, delivery_at, order_base_code, order_config_id, order_note, checked_on,
                                    schedule_changed_on, maintenance_note, extra)
  select w, src.airline_id, src.reg, src.type_id, src.config_id, src.base,
         case when src.tv is not null then 'active' when src.delivery_at <= now() then 'delivered' else 'on_order' end,
         private.json_date(src.dv -> 'date'), src.delivery_at, src.order_base, src.order_config_id, src.dv ->> 'plan',
         private.json_date(src.tv -> 'checkedOn'), private.json_date(src.tv -> 'schedChangedOn'), src.tv ->> 'maint',
         jsonb_strip_nulls(jsonb_build_object(
           'tails_index', case when src.tv is not null then coalesce(src.ti, (src.old_extra ->> 'tails_index')::int) end,
           'deliveries_index', case when src.dv is not null then coalesce(src.di, (src.old_extra ->> 'deliveries_index')::int) end,
           'tail', case when src.tv is not null then nullif(private.planner_extra(src.tv, k_tail, src.old_extra -> 'tail'), '{}'::jsonb) end,
           'delivery', case when src.dv is not null then nullif(private.planner_extra(src.dv, k_delivery, src.old_extra -> 'delivery'), '{}'::jsonb) end))
    from src order by coalesce(src.ti, 100000 + src.di)
  on conflict (world_id, registration) do update set airline_id = excluded.airline_id,
    aircraft_type_id = excluded.aircraft_type_id, cabin_config_id = excluded.cabin_config_id, base_code = excluded.base_code,
    status = excluded.status, ordered_on = excluded.ordered_on, delivery_at = excluded.delivery_at,
    order_base_code = excluded.order_base_code, order_config_id = excluded.order_config_id, order_note = excluded.order_note,
    checked_on = excluded.checked_on, schedule_changed_on = excluded.schedule_changed_on,
    maintenance_note = excluded.maintenance_note, retired_on = null, extra = excluded.extra
  where (x.airline_id, x.aircraft_type_id, x.cabin_config_id, x.base_code, x.status, x.ordered_on, x.delivery_at,
         x.order_base_code, x.order_config_id, x.order_note, x.checked_on, x.schedule_changed_on, x.maintenance_note,
         x.retired_on, x.extra)
        is distinct from (excluded.airline_id, excluded.aircraft_type_id, excluded.cabin_config_id, excluded.base_code,
                          excluded.status, excluded.ordered_on, excluded.delivery_at, excluded.order_base_code,
                          excluded.order_config_id, excluded.order_note, excluded.checked_on, excluded.schedule_changed_on,
                          excluded.maintenance_note, null::date, excluded.extra);
  get diagnostics n = row_count; v_out := v_out || jsonb_build_object('aircraft', n);

  -- the others keep their place in each list (it moves when an item before them goes)
  update public.aircraft a set extra = jsonb_set(a.extra, '{tails_index}', to_jsonb(p.new_pos))
    from pg_temp.t_pa p
   where p.section = 'tails' and p.state = 'same' and a.world_id = w and a.registration = p.key
     and a.extra ? 'tails_index' and (a.extra -> 'tails_index') is distinct from to_jsonb(p.new_pos);
  get diagnostics n = row_count; v_out := v_out || jsonb_build_object('tails moved', n);
  update public.aircraft a set extra = jsonb_set(a.extra, '{deliveries_index}', to_jsonb(p.new_pos))
    from pg_temp.t_pa p
   where p.section = 'deliveries' and p.state = 'same' and a.world_id = w and a.registration = p.key
     and a.extra ? 'deliveries_index' and (a.extra -> 'deliveries_index') is distinct from to_jsonb(p.new_pos);
  get diagnostics n = row_count; v_out := v_out || jsonb_build_object('deliveries moved', n);
  return v_out;
end
$function$;

-- Frequencies and plan cards. A frequency is a rotation and its two legs in UTC, worked out exactly as the loader does
-- (design §4: the outbound's local weekdays and times at the hub, the return's day by the old planner's rule, block
-- times from the typed times). A plan card's legs are in UTC like flight legs, one row per place on the card.
create or replace function private.planner_apply_flights(p_world_id bigint)
 returns jsonb
 language plpgsql
 set search_path to ''
as $function$
declare w bigint := p_world_id; n int; v_out jsonb := '{}'::jsonb;
  k_freq text[] := array['id', 'routeKey', 'days', 'tail', 'noOut', 'noBack', 'depHub', 'arrDest', 'depDest', 'arrHub',
                         'service', 'price', 'launched', 'notes'];
  k_plan text[] := array['base', 'title', 'note', 'legs'];
begin
  -- ---- frequencies
  if exists (select 1 from pg_temp.t_pa where section = 'freqs' and state = 'changed') then
    delete from public.rotations r using pg_temp.t_pa p
     where p.section = 'freqs' and p.state = 'changed' and p.new_item is null and r.world_id = w and r.legacy_key = p.key;
    get diagnostics n = row_count; v_out := v_out || jsonb_build_object('rotations removed', n);

    if to_regclass('pg_temp.t_pa_freqs') is null then
      create temporary table t_pa_freqs (
        legacy_key text primary key, ord bigint, v jsonb, airline_id bigint, route_id bigint, hub text, dest text,
        aircraft_id bigint, old_extra jsonb, l1_days smallint[], l1_dep smallint, l1_block smallint, l2_days smallint[],
        l2_dep smallint, l2_block smallint) on commit drop;
    end if;
    truncate pg_temp.t_pa_freqs;
    insert into pg_temp.t_pa_freqs
    select y.k, y.ord, y.v, y.airline_id, y.route_id, y.hub_code, y.dest_code, y.aircraft_id, y.old_extra,
           private.shift_weekdays(y.days_local, y.s1), y.l1_dep, y.out_block,
           private.shift_weekdays(private.shift_weekdays(y.days_local, y.back_day), y.s2), y.l2_dep, y.l2_block
      from (
        select x.*,
               case when x.dep_h is not null then ((x.dep_h - x.oh) % 1440 + 1440) % 1440 end as l1_dep,
               case when x.dep_h is not null then floor((x.dep_h - x.oh) / 1440.0)::int else 0 end as s1,
               -- the return's day after the outbound's local day (the old planner's computeFreq): the outbound's arrival
               -- day, or the next one if the return departs earlier than that arrival
               case when x.dep_h is not null and x.out_block is not null and x.dep_d is not null
                    then floor((x.dep_h + x.out_block + x.od - x.oh) / 1440.0)::int
                         + case when x.dep_d < (((x.dep_h + x.out_block + x.od - x.oh) % 1440) + 1440) % 1440 then 1 else 0 end
                    else 0 end as back_day,
               case when x.dep_d is not null then ((x.dep_d - x.od) % 1440 + 1440) % 1440 end as l2_dep,
               case when x.dep_d is not null then floor((x.dep_d - x.od) / 1440.0)::int else 0 end as s2,
               case when x.dep_d is not null and x.arr_h is not null then ((x.arr_h - x.dep_d - (x.oh - x.od)) % 1440 + 1440) % 1440 end as l2_block
          from (
            select f.key as k, f.new_pos as ord, f.new_item as v, al.id as airline_id, ro.id as route_id, ro.hub_code, ro.dest_code,
                   ac.id as aircraft_id, old.extra as old_extra,
                   coalesce(private.weekday_set(f.new_item ->> 'days'), '{1,2,3,4,5,6,7}') as days_local,
                   t.dep_h, t.arr_d, t.dep_d, t.arr_h, o.oh, o.od,
                   case when t.dep_h is not null and t.arr_d is not null
                        then ((t.arr_d - t.dep_h - (o.od - o.oh)) % 1440 + 1440) % 1440 end as out_block
              from pg_temp.t_pa f
              join public.airlines al on al.world_id = w and al.planner_name = split_part(f.new_item ->> 'routeKey', '|', 1)
              join public.routes ro on ro.airline_id = al.id and ro.hub_code = split_part(f.new_item ->> 'routeKey', '|', 2)
                                   and ro.dest_code = split_part(f.new_item ->> 'routeKey', '|', 3)
              left join public.aircraft ac on ac.world_id = w and ac.registration = f.new_item ->> 'tail'
              left join public.rotations old on old.world_id = w and old.legacy_key = f.key
              left join public.airports ah on ah.code = ro.hub_code
              left join public.world_airports wh on wh.world_id = w and wh.airport_code = ro.hub_code
              left join public.airports ad on ad.code = ro.dest_code
              left join public.world_airports wd on wd.world_id = w and wd.airport_code = ro.dest_code
              -- each end's offset in minutes; an airport whose offset isn't known counts as UTC, as the planner counts it
              cross join lateral (select round(coalesce(wh.utc_offset_override, ah.utc_offset, 0) * 60)::int as oh,
                                         round(coalesce(wd.utc_offset_override, ad.utc_offset, 0) * 60)::int as od) o
              cross join lateral (select private.clock_min(f.new_item ->> 'depHub') as dep_h, private.clock_min(f.new_item ->> 'arrDest') as arr_d,
                                         private.clock_min(f.new_item ->> 'depDest') as dep_d, private.clock_min(f.new_item ->> 'arrHub') as arr_h) t
             where f.section = 'freqs' and f.state = 'changed' and f.new_item is not null
            ) x) y;

    -- a rotation moving to another route takes its legs with it: they are written again below
    delete from public.flight_legs l using public.rotations r, pg_temp.t_pa_freqs f
     where l.rotation_id = r.id and r.world_id = w and r.legacy_key = f.legacy_key and r.route_id <> f.route_id;
    insert into public.rotations as x (world_id, airline_id, route_id, legacy_key, service_code, fare_pct, launched_on, note, extra)
    select w, f.airline_id, f.route_id, f.legacy_key, f.v ->> 'service',
           (select v from private.json_num(f.v -> 'price') v where abs(v) < 10000), private.json_date(f.v -> 'launched'),
           f.v ->> 'notes', private.planner_extra(f.v, k_freq, f.old_extra)
      from pg_temp.t_pa_freqs f order by f.ord
    on conflict (world_id, legacy_key) do update set airline_id = excluded.airline_id, route_id = excluded.route_id,
      service_code = excluded.service_code, fare_pct = excluded.fare_pct, launched_on = excluded.launched_on,
      note = excluded.note, extra = excluded.extra
    where (x.airline_id, x.route_id, x.service_code, x.fare_pct, x.launched_on, x.note, x.extra)
          is distinct from (excluded.airline_id, excluded.route_id, excluded.service_code, excluded.fare_pct,
                            excluded.launched_on, excluded.note, excluded.extra);
    get diagnostics n = row_count; v_out := v_out || jsonb_build_object('rotations', n);
    insert into public.flight_legs as x (world_id, airline_id, rotation_id, leg_no, flight_no, origin_code, dest_code, aircraft_id,
                                         days_utc, dep_utc_min, block_min)
    select w, f.airline_id, r.id, g.leg_no,
           (select v::int from private.json_int(f.v -> case g.leg_no when 1 then 'noOut' else 'noBack' end) v where v between 0 and 2000000000),
           case g.leg_no when 1 then f.hub else f.dest end, case g.leg_no when 1 then f.dest else f.hub end, f.aircraft_id,
           case g.leg_no when 1 then f.l1_days else f.l2_days end,
           case g.leg_no when 1 then f.l1_dep else f.l2_dep end,
           case g.leg_no when 1 then f.l1_block else f.l2_block end
      from pg_temp.t_pa_freqs f
      join public.rotations r on r.world_id = w and r.legacy_key = f.legacy_key
      cross join (values (1::smallint), (2::smallint)) as g(leg_no)
     order by f.ord, g.leg_no
    on conflict (rotation_id, leg_no) do update set airline_id = excluded.airline_id, flight_no = excluded.flight_no,
      origin_code = excluded.origin_code, dest_code = excluded.dest_code, aircraft_id = excluded.aircraft_id,
      days_utc = excluded.days_utc, dep_utc_min = excluded.dep_utc_min, block_min = excluded.block_min
    where (x.airline_id, x.flight_no, x.origin_code, x.dest_code, x.aircraft_id, x.days_utc, x.dep_utc_min, x.block_min)
          is distinct from (excluded.airline_id, excluded.flight_no, excluded.origin_code, excluded.dest_code,
                            excluded.aircraft_id, excluded.days_utc, excluded.dep_utc_min, excluded.block_min);
    get diagnostics n = row_count; v_out := v_out || jsonb_build_object('flight_legs', n);
  end if;

  -- ---- plan cards (keyed by registration) and their legs
  if exists (select 1 from pg_temp.t_pa where section = 'plans' and state = 'changed') then
    delete from public.plan_cards c using pg_temp.t_pa p, public.aircraft a
     where p.section = 'plans' and p.state = 'changed' and p.new_item is null
       and a.world_id = w and a.registration = p.key and c.aircraft_id = a.id;
    get diagnostics n = row_count; v_out := v_out || jsonb_build_object('plan_cards removed', n);
    insert into public.plan_cards as x (world_id, airline_id, aircraft_id, base_code, title, note, extra)
    select w, a.airline_id, a.id, (select ap.code from public.airports ap where ap.code = p.new_item ->> 'base'),
           p.new_item ->> 'title', p.new_item ->> 'note', private.planner_extra(p.new_item, k_plan, old.extra)
      from pg_temp.t_pa p
      join public.aircraft a on a.world_id = w and a.registration = p.key
      left join public.plan_cards old on old.aircraft_id = a.id
     where p.section = 'plans' and p.state = 'changed' and jsonb_typeof(p.new_item) = 'object'
     order by p.key
    on conflict (aircraft_id) do update set airline_id = excluded.airline_id, base_code = excluded.base_code,
      title = excluded.title, note = excluded.note, extra = excluded.extra
    where (x.airline_id, x.base_code, x.title, x.note, x.extra)
          is distinct from (excluded.airline_id, excluded.base_code, excluded.title, excluded.note, excluded.extra);
    get diagnostics n = row_count; v_out := v_out || jsonb_build_object('plan_cards', n);
    with src as (
      select c.id as plan_card_id, (e.ord)::int as position, l,
             (select ap.code from public.airports ap where ap.code = l ->> 'from') as origin,
             (select ap.code from public.airports ap where ap.code = l ->> 'to') as dest
        from pg_temp.t_pa p
        join public.aircraft a on a.world_id = w and a.registration = p.key
        join public.plan_cards c on c.aircraft_id = a.id
        cross join lateral jsonb_array_elements(case when jsonb_typeof(p.new_item -> 'legs') = 'array' then p.new_item -> 'legs' else '[]'::jsonb end) with ordinality as e(l, ord)
       where p.section = 'plans' and p.state = 'changed' and jsonb_typeof(p.new_item) = 'object' and jsonb_typeof(l) = 'object'),
    timed as (
      select src.*, private.clock_min(src.l ->> 'dep') as dep,
             (select m[1]::int * 60 + m[2]::int from regexp_match(btrim(src.l ->> 'block'), '^(\d{1,3}):([0-5]\d)$') m) as block,
             round(coalesce(wo.utc_offset_override, ao.utc_offset, 0) * 60)::int as oo
        from src
        left join public.airports ao on ao.code = src.origin
        left join public.world_airports wo on wo.world_id = w and wo.airport_code = src.origin)
    insert into public.plan_card_legs as x (world_id, plan_card_id, position, flight_no, origin_code, dest_code, dep_utc_min,
                                            block_min, service_code)
    select w, t.plan_card_id, t.position,
           (select v::int from private.json_int(t.l -> 'no') v where v between 0 and 2000000000), t.origin, t.dest,
           case when t.dep is not null then ((t.dep - t.oo) % 1440 + 1440) % 1440 end,
           case when t.block < 32000 then t.block end, t.l ->> 'svc'
      from timed t order by t.plan_card_id, t.position
    on conflict (plan_card_id, position) do update set flight_no = excluded.flight_no, origin_code = excluded.origin_code,
      dest_code = excluded.dest_code, dep_utc_min = excluded.dep_utc_min, block_min = excluded.block_min,
      service_code = excluded.service_code
    where (x.flight_no, x.origin_code, x.dest_code, x.dep_utc_min, x.block_min, x.service_code)
          is distinct from (excluded.flight_no, excluded.origin_code, excluded.dest_code, excluded.dep_utc_min,
                            excluded.block_min, excluded.service_code);
    get diagnostics n = row_count; v_out := v_out || jsonb_build_object('plan_card_legs', n);
    delete from public.plan_card_legs x using pg_temp.t_pa p, public.aircraft a, public.plan_cards c
     where p.section = 'plans' and p.state = 'changed' and jsonb_typeof(p.new_item) = 'object'
       and a.world_id = w and a.registration = p.key and c.aircraft_id = a.id and x.plan_card_id = c.id
       and x.position > coalesce(jsonb_array_length(case when jsonb_typeof(p.new_item -> 'legs') = 'array' then p.new_item -> 'legs' end), 0);
  end if;
  return v_out;
end
$function$;

-- The work lists: to-dos and their steps, fare plan, interline, monthly checks, dismissed alerts, kept cabins, money
-- spent and growth moves. Money spent and growth moves have no id: entries are added and removed by what they say (the
-- latest of identical ones goes first), and when the stored order no longer matches the document's (an entry changed in
-- place), the rest of the list from the first entry out of place is written again in order, unless p_keep_order is
-- false (an entry was skipped, so the document's order isn't the one to keep).
create or replace function private.planner_apply_work(p_world_id bigint, p_keep_order boolean)
 returns jsonb
 language plpgsql
 set search_path to ''
as $function$
declare w bigint := p_world_id; n int; v_out jsonb := '{}'::jsonb; v_first bigint;
  k_todo text[] := array['id', 'title', 'date', 'done', 'doneAt', 'created', 'note', 'items'];
  k_fare text[] := array['id', 'airline', 'routeKey', 'cls', 'pct', 'from', 'proposed', 'status', 'why'];
begin
  -- ---- to-dos and their steps
  if exists (select 1 from pg_temp.t_pa where section = 'todos' and state = 'changed') then
    delete from public.todos t using pg_temp.t_pa p
     where p.section = 'todos' and p.state = 'changed' and p.new_item is null and t.world_id = w and t.legacy_key = p.key;
    get diagnostics n = row_count; v_out := v_out || jsonb_build_object('todos removed', n);
    insert into public.todos as x (world_id, legacy_key, title, due_on, done, done_at, note, created_at, extra)
    select w, p.key, coalesce(v ->> 'title', ''), private.json_date(v -> 'date'), coalesce(v -> 'done' = 'true'::jsonb, false),
           private.json_ts(v -> 'doneAt'), v ->> 'note',
           -- a to-do with no creation time of its own keeps the one it has
           coalesce(private.json_ts(v -> 'created'), old.created_at, now()),
           private.planner_extra(v, k_todo, old.extra)
      from pg_temp.t_pa p cross join lateral (select p.new_item as v) i
      left join public.todos old on old.world_id = w and old.legacy_key = p.key
     where p.section = 'todos' and p.state = 'changed' and p.new_item is not null
     order by p.new_pos
    on conflict (world_id, legacy_key) do update set title = excluded.title, due_on = excluded.due_on, done = excluded.done,
      done_at = excluded.done_at, note = excluded.note, created_at = excluded.created_at, extra = excluded.extra
    where (x.title, x.due_on, x.done, x.done_at, x.note, x.created_at, x.extra)
          is distinct from (excluded.title, excluded.due_on, excluded.done, excluded.done_at, excluded.note,
                            excluded.created_at, excluded.extra);
    get diagnostics n = row_count; v_out := v_out || jsonb_build_object('todos', n);
    insert into public.todo_items as x (world_id, todo_id, position, body)
    select w, t.id, (e.ord)::int, case when jsonb_typeof(e.i) = 'string' then e.i #>> '{}' else e.i::text end
      from pg_temp.t_pa p
      join public.todos t on t.world_id = w and t.legacy_key = p.key
      cross join lateral jsonb_array_elements(case when jsonb_typeof(p.new_item -> 'items') = 'array' then p.new_item -> 'items' else '[]'::jsonb end) with ordinality as e(i, ord)
     where p.section = 'todos' and p.state = 'changed' and p.new_item is not null
     order by t.id, e.ord
    on conflict (todo_id, position) do update set body = excluded.body where x.body is distinct from excluded.body;
    get diagnostics n = row_count; v_out := v_out || jsonb_build_object('todo_items', n);
    delete from public.todo_items x using pg_temp.t_pa p, public.todos t
     where p.section = 'todos' and p.state = 'changed' and p.new_item is not null
       and t.world_id = w and t.legacy_key = p.key and x.todo_id = t.id
       and x.position > coalesce(jsonb_array_length(case when jsonb_typeof(p.new_item -> 'items') = 'array' then p.new_item -> 'items' end), 0);
  end if;

  -- ---- fare plan
  if exists (select 1 from pg_temp.t_pa where section = 'farePlan' and state = 'changed') then
    delete from public.fare_plan t using pg_temp.t_pa p
     where p.section = 'farePlan' and p.state = 'changed' and p.new_item is null and t.world_id = w and t.legacy_key = p.key;
    insert into public.fare_plan as x (world_id, airline_id, route_id, legacy_key, cabin_class, change_pct, fare_from,
                                       proposed_on, status, reason, extra)
    select w, al.id,
           (select r.id from public.routes r join public.airlines ra on ra.id = r.airline_id
             where r.world_id = w and ra.planner_name || '|' || r.hub_code || '|' || r.dest_code = v ->> 'routeKey'),
           p.key, case when v ->> 'cls' in ('economy', 'business', 'first') then v ->> 'cls' end,
           (select x2 from private.json_num(v -> 'pct') x2 where abs(x2) < 10000),
           (select x2 from private.json_num(v -> 'from') x2 where abs(x2) < 1000000000000),
           private.json_date(v -> 'proposed'), case when v ->> 'status' = 'dropped' then 'dropped' else 'planned' end,
           v ->> 'why', private.planner_extra(v, k_fare, old.extra)
      from pg_temp.t_pa p cross join lateral (select p.new_item as v) i
      join public.airlines al on al.world_id = w and al.planner_name = v ->> 'airline'
      left join public.fare_plan old on old.world_id = w and old.legacy_key = p.key
     where p.section = 'farePlan' and p.state = 'changed' and p.new_item is not null
     order by p.new_pos
    on conflict (world_id, legacy_key) do update set airline_id = excluded.airline_id, route_id = excluded.route_id,
      cabin_class = excluded.cabin_class, change_pct = excluded.change_pct, fare_from = excluded.fare_from,
      proposed_on = excluded.proposed_on, status = excluded.status, reason = excluded.reason, extra = excluded.extra
    where (x.airline_id, x.route_id, x.cabin_class, x.change_pct, x.fare_from, x.proposed_on, x.status, x.reason, x.extra)
          is distinct from (excluded.airline_id, excluded.route_id, excluded.cabin_class, excluded.change_pct,
                            excluded.fare_from, excluded.proposed_on, excluded.status, excluded.reason, excluded.extra);
    get diagnostics n = row_count; v_out := v_out || jsonb_build_object('fare_plan', n);
  end if;

  -- ---- interline, keyed "Airline|country": the planner's "requested" is to_sign
  if exists (select 1 from pg_temp.t_pa where section = 'interline' and state = 'changed') then
    delete from public.interline_agreements x using pg_temp.t_pa p, public.airlines al
     where p.section = 'interline' and p.state = 'changed' and p.new_item is null
       and al.world_id = w and al.planner_name = split_part(p.key, '|', 1)
       and x.airline_id = al.id and x.country_code = substr(p.key, strpos(p.key, '|') + 1);
    insert into public.interline_agreements as x (world_id, airline_id, country_code, status, partner, decided_on, note)
    select w, al.id, substr(p.key, strpos(p.key, '|') + 1),
           case when v ->> 'status' in ('signed', 'declined', 'nopartner') then v ->> 'status' else 'to_sign' end,
           v ->> 'partner', private.json_date(v -> 'date'), v ->> 'notes'
      from pg_temp.t_pa p cross join lateral (select p.new_item as v) i
      join public.airlines al on al.world_id = w and al.planner_name = split_part(p.key, '|', 1)
     where p.section = 'interline' and p.state = 'changed' and jsonb_typeof(p.new_item) = 'object'
       and exists (select 1 from public.countries c where c.code = substr(p.key, strpos(p.key, '|') + 1))
    on conflict (airline_id, country_code) do update set status = excluded.status, partner = excluded.partner,
      decided_on = excluded.decided_on, note = excluded.note
    where (x.status, x.partner, x.decided_on, x.note) is distinct from (excluded.status, excluded.partner, excluded.decided_on, excluded.note);
    get diagnostics n = row_count; v_out := v_out || jsonb_build_object('interline_agreements', n);
  end if;

  -- ---- monthly checks, keyed "Airline|task": "Equinox" is the group as a whole
  if exists (select 1 from pg_temp.t_pa where section = 'monthly' and state = 'changed') then
    delete from public.monthly_checks x using pg_temp.t_pa p
     where p.section = 'monthly' and p.state = 'changed' and p.new_item is null and x.world_id = w
       and x.task = substr(p.key, strpos(p.key, '|') + 1)
       and x.airline_id is not distinct from (select al.id from public.airlines al where al.world_id = w and al.planner_name = split_part(p.key, '|', 1)
                                                 and split_part(p.key, '|', 1) <> 'Equinox');
    insert into public.monthly_checks as x (world_id, airline_id, task, last_done_on)
    select w, al.id, substr(p.key, strpos(p.key, '|') + 1), private.json_date(p.new_item)
      from pg_temp.t_pa p
      left join public.airlines al on al.world_id = w and al.planner_name = split_part(p.key, '|', 1) and split_part(p.key, '|', 1) <> 'Equinox'
     where p.section = 'monthly' and p.state = 'changed' and p.new_item is not null
       and (split_part(p.key, '|', 1) = 'Equinox' or al.id is not null)
    on conflict on constraint monthly_checks_world_airline_task_key do update set last_done_on = excluded.last_done_on
    where x.last_done_on is distinct from excluded.last_done_on;
    get diagnostics n = row_count; v_out := v_out || jsonb_build_object('monthly_checks', n);
  end if;

  -- ---- Home's dismissed alerts
  if exists (select 1 from pg_temp.t_pa where section = 'dismissed' and state = 'changed') then
    delete from public.dismissals x using pg_temp.t_pa p
     where p.section = 'dismissed' and p.state = 'changed' and p.new_item is null and x.world_id = w and x.alert_key = p.key;
    insert into public.dismissals as x (world_id, alert_key, dismissed_on)
    select w, p.key, private.json_date(p.new_item) from pg_temp.t_pa p
     where p.section = 'dismissed' and p.state = 'changed' and p.new_item is not null
    on conflict (world_id, alert_key) do update set dismissed_on = excluded.dismissed_on
    where x.dismissed_on is distinct from excluded.dismissed_on;
    get diagnostics n = row_count; v_out := v_out || jsonb_build_object('dismissals', n);
  end if;

  -- ---- "keep this cabin" decisions, keyed "REG|Cabin"
  if exists (select 1 from pg_temp.t_pa where section = 'cabinKeep' and state = 'changed') then
    delete from public.aircraft_cabin_keeps x using pg_temp.t_pa p, public.aircraft a
     where p.section = 'cabinKeep' and p.state = 'changed' and p.new_item is null
       and a.world_id = w and a.registration = split_part(p.key, '|', 1)
       and x.aircraft_id = a.id and x.cabin = substr(p.key, strpos(p.key, '|') + 1);
    insert into public.aircraft_cabin_keeps as x (world_id, aircraft_id, cabin, decided_on)
    select w, a.id, substr(p.key, strpos(p.key, '|') + 1), private.json_date(p.new_item -> 'date')
      from pg_temp.t_pa p join public.aircraft a on a.world_id = w and a.registration = split_part(p.key, '|', 1)
     where p.section = 'cabinKeep' and p.state = 'changed' and p.new_item is not null
       and substr(p.key, strpos(p.key, '|') + 1) in ('Standard', 'Leisure', 'Leisure Plus', 'Comfort')
    on conflict (aircraft_id, cabin) do update set decided_on = excluded.decided_on where x.decided_on is distinct from excluded.decided_on;
    get diagnostics n = row_count; v_out := v_out || jsonb_build_object('aircraft_cabin_keeps', n);
  end if;

  -- ---- money spent (capex)
  if exists (select 1 from pg_temp.t_pa where section = 'capex' and state = 'changed') then
    with gone as (select p.grp, count(*) as n from pg_temp.t_pa p
                   where p.section = 'capex' and p.state = 'changed' and p.new_item is null group by p.grp),
    stored as (select s.id, row_number() over (partition by k.k order by s.id desc) as rn, k.k
                 from public.spending_log s join public.airlines al on al.id = s.airline_id
                 cross join lateral (select private.capex_key(al.planner_name, s.spent_on, s.kind, s.amount, s.note) as k) k
                where s.world_id = w)
    delete from public.spending_log s using stored r join gone g on g.grp = r.k where s.id = r.id and r.rn <= g.n;
    get diagnostics n = row_count; v_out := v_out || jsonb_build_object('spending_log removed', n);
    insert into public.spending_log (world_id, airline_id, spent_on, amount, kind, aircraft_id, note)
    select w, al.id, private.json_date(v -> 'date'), round(private.json_num(v -> 'amountM') * 1000000, 2),
           case when v ->> 'kind' in ('order', 'cabin', 'loss') then v ->> 'kind' else 'order' end,
           -- the aircraft, where the note starts with one of the airline's registrations
           (select a.id from public.aircraft a where a.world_id = w and a.airline_id = al.id
               and a.registration = split_part(btrim(coalesce(v ->> 'note', '')), ' ', 1)),
           v ->> 'note'
      from pg_temp.t_pa p cross join lateral (select p.new_item as v) i
      join public.airlines al on al.world_id = w and al.planner_name = v ->> 'airline'
     where p.section = 'capex' and p.state = 'changed' and p.new_item is not null and p.cur_item is null and p.grp not like 'unparsed %'
     order by p.new_pos;
    get diagnostics n = row_count; v_out := v_out || jsonb_build_object('spending_log', n);
    if p_keep_order then
      with stored as (
        select s.id, k.k || '#' || row_number() over (partition by k.k order by s.id) as kk, row_number() over (order by s.id) as rn
          from public.spending_log s join public.airlines al on al.id = s.airline_id
          cross join lateral (select private.capex_key(al.planner_name, s.spent_on, s.kind, s.amount, s.note) as k) k
         where s.world_id = w),
      wanted as (
        select p.key as kk, row_number() over (order by p.new_pos) as rn from pg_temp.t_pa p
         where p.section = 'capex' and p.new_item is not null and p.grp not like 'unparsed %'
           and exists (select 1 from public.airlines al where al.world_id = w and al.planner_name = p.new_item ->> 'airline'))
      select min(coalesce(s.rn, x.rn)) into v_first from stored s full join wanted x on x.rn = s.rn where s.kk is distinct from x.kk;
      if v_first is not null then
        delete from public.spending_log s
         where s.id in (select id from (select s2.id, row_number() over (order by s2.id) as rn from public.spending_log s2 where s2.world_id = w) z
                         where z.rn >= v_first);
        insert into public.spending_log (world_id, airline_id, spent_on, amount, kind, aircraft_id, note)
        select w, al.id, private.json_date(v -> 'date'), round(private.json_num(v -> 'amountM') * 1000000, 2),
               case when v ->> 'kind' in ('order', 'cabin', 'loss') then v ->> 'kind' else 'order' end,
               (select a.id from public.aircraft a where a.world_id = w and a.airline_id = al.id
                   and a.registration = split_part(btrim(coalesce(v ->> 'note', '')), ' ', 1)),
               v ->> 'note'
          from (select p.new_item as v, row_number() over (order by p.new_pos) as rn from pg_temp.t_pa p
                 where p.section = 'capex' and p.new_item is not null and p.grp not like 'unparsed %'
                   and exists (select 1 from public.airlines al where al.world_id = w and al.planner_name = p.new_item ->> 'airline')) x
          join public.airlines al on al.world_id = w and al.planner_name = x.v ->> 'airline'
         where x.rn >= v_first
         order by x.rn;
        get diagnostics n = row_count; v_out := v_out || jsonb_build_object('spending_log written again in order', n);
      end if;
    end if;
  end if;

  -- ---- growth moves (growthLog)
  if exists (select 1 from pg_temp.t_pa where section = 'growthLog' and state = 'changed') then
    with gone as (select p.grp, count(*) as n from pg_temp.t_pa p
                   where p.section = 'growthLog' and p.state = 'changed' and p.new_item is null group by p.grp),
    stored as (select g.id, row_number() over (partition by k.k order by g.id desc) as rn, k.k
                 from public.growth_log g join public.airlines al on al.id = g.airline_id
                 cross join lateral (select private.growth_key(al.planner_name, g.logged_on, g.move, g.note) as k) k
                where g.world_id = w)
    delete from public.growth_log g using stored r join gone x on x.grp = r.k where g.id = r.id and r.rn <= x.n;
    get diagnostics n = row_count; v_out := v_out || jsonb_build_object('growth_log removed', n);
    insert into public.growth_log (world_id, airline_id, logged_on, move, note)
    select w, al.id, private.json_date(p.new_item -> 'date'), p.new_item ->> 'move', p.new_item ->> 'note'
      from pg_temp.t_pa p join public.airlines al on al.world_id = w and al.planner_name = p.new_item ->> 'airline'
     where p.section = 'growthLog' and p.state = 'changed' and p.new_item is not null and p.cur_item is null and p.grp not like 'unparsed %'
     order by p.new_pos;
    get diagnostics n = row_count; v_out := v_out || jsonb_build_object('growth_log', n);
    if p_keep_order then
      with stored as (
        select g.id, k.k || '#' || row_number() over (partition by k.k order by g.id) as kk, row_number() over (order by g.id) as rn
          from public.growth_log g join public.airlines al on al.id = g.airline_id
          cross join lateral (select private.growth_key(al.planner_name, g.logged_on, g.move, g.note) as k) k
         where g.world_id = w),
      wanted as (
        select p.key as kk, row_number() over (order by p.new_pos) as rn from pg_temp.t_pa p
         where p.section = 'growthLog' and p.new_item is not null and p.grp not like 'unparsed %'
           and exists (select 1 from public.airlines al where al.world_id = w and al.planner_name = p.new_item ->> 'airline'))
      select min(coalesce(s.rn, x.rn)) into v_first from stored s full join wanted x on x.rn = s.rn where s.kk is distinct from x.kk;
      if v_first is not null then
        delete from public.growth_log g
         where g.id in (select id from (select g2.id, row_number() over (order by g2.id) as rn from public.growth_log g2 where g2.world_id = w) z
                         where z.rn >= v_first);
        insert into public.growth_log (world_id, airline_id, logged_on, move, note)
        select w, al.id, private.json_date(x.v -> 'date'), x.v ->> 'move', x.v ->> 'note'
          from (select p.new_item as v, row_number() over (order by p.new_pos) as rn from pg_temp.t_pa p
                 where p.section = 'growthLog' and p.new_item is not null and p.grp not like 'unparsed %'
                   and exists (select 1 from public.airlines al where al.world_id = w and al.planner_name = p.new_item ->> 'airline')) x
          join public.airlines al on al.world_id = w and al.planner_name = x.v ->> 'airline'
         where x.rn >= v_first
         order by x.rn;
        get diagnostics n = row_count; v_out := v_out || jsonb_build_object('growth_log written again in order', n);
      end if;
    end if;
  end if;
  return v_out;
end
$function$;

-- Cash and next-7-day costs (design §8): for each airline and date a changed item names, a cash_entries row holds a
-- figure only where it differs from the capture's (capture_cash, rounded as the planner rounds), in AS$, and goes once
-- both agree again; the getter shows the capture's figure otherwise.
create or replace function private.planner_apply_money(p_world_id bigint)
 returns jsonb
 language plpgsql
 set search_path to ''
as $function$
declare w bigint := p_world_id; n int; m int;
begin
  if not exists (select 1 from pg_temp.t_pa where section in ('cash', 'fixed7') and state = 'changed') then return '{}'::jsonb; end if;
  if to_regclass('pg_temp.t_pa_cash') is null then
    create temporary table t_pa_cash (airline_id bigint, day date, cash numeric, fixed_next7 numeric,
                                      primary key (airline_id, day)) on commit drop;
  end if;
  truncate pg_temp.t_pa_cash;
  with pairs as (
    select distinct split_part(p.key, '|', 1) as day_key, substr(p.key, strpos(p.key, '|') + 1) as airline_name
      from pg_temp.t_pa p where p.section in ('cash', 'fixed7') and p.state = 'changed'),
  src as (
    select al.id as airline_id, private.json_date(to_jsonb(x.day_key)) as day,
           private.json_num((select q.eff_item from pg_temp.t_pa q where q.section = 'cash' and q.key = x.day_key || '|' || x.airline_name)) as st_cash,
           private.json_num((select q.eff_item from pg_temp.t_pa q where q.section = 'fixed7' and q.key = x.day_key || '|' || x.airline_name)) as st_fixed
      from pairs x join public.airlines al on al.world_id = w and al.planner_name = x.airline_name),
  cap as (
    select cc.airline_id, cc.day, floor(cc.cash / 10000 + 0.5) / 100 as cash_m,
           case when cc.fixed_next7 > 0 then floor(cc.fixed_next7 / 10000 + 0.5) / 100 end as fixed_m
      from public.capture_cash cc where cc.world_id = w and cc.airline_id in (select airline_id from src))
  insert into pg_temp.t_pa_cash
  select s.airline_id, s.day,
         case when s.st_cash is not null and s.st_cash is distinct from c.cash_m and abs(s.st_cash) < 1000000 then round(s.st_cash * 1000000, 2) end,
         case when s.st_fixed is not null and s.st_fixed is distinct from c.fixed_m and abs(s.st_fixed) < 1000000 then round(s.st_fixed * 1000000, 2) end
    from src s left join cap c on c.airline_id = s.airline_id and c.day = s.day
   where s.day is not null;
  insert into public.cash_entries as x (world_id, airline_id, day, cash, fixed_next7, entered_at)
  select w, c.airline_id, c.day, c.cash, c.fixed_next7, now() from pg_temp.t_pa_cash c
   where c.cash is not null or c.fixed_next7 is not null
  on conflict (airline_id, day) do update set cash = excluded.cash, fixed_next7 = excluded.fixed_next7, entered_at = excluded.entered_at
  where (x.cash, x.fixed_next7) is distinct from (excluded.cash, excluded.fixed_next7);
  get diagnostics n = row_count;
  delete from public.cash_entries x using pg_temp.t_pa_cash c
   where x.airline_id = c.airline_id and x.day = c.day and c.cash is null and c.fixed_next7 is null;
  get diagnostics m = row_count;
  return jsonb_build_object('cash_entries', n, 'cash_entries removed', m);
end
$function$;

-- What the saved document no longer has, once everything that pointed at it is written: an aircraft in neither list
-- (retired while the capture's flights or payments or money spent point at it, removed where nothing does, otherwise
-- just out of both lists); a route nothing adds, edits, flies or plans any more and the research doesn't have; and
-- markets, cabin layouts, types and services no longer listed, unless something still uses them (as the loader does).
create or replace function private.planner_apply_tidy(p_world_id bigint)
 returns jsonb
 language plpgsql
 set search_path to ''
as $function$
declare w bigint := p_world_id; n int; v_out jsonb := '{}'::jsonb;
begin
  if exists (select 1 from pg_temp.t_pa where section in ('tails', 'deliveries') and state = 'changed') then
    if to_regclass('pg_temp.t_pa_gone') is null then
      create temporary table t_pa_gone (id bigint primary key) on commit drop;
    end if;
    truncate pg_temp.t_pa_gone;
    insert into pg_temp.t_pa_gone
    select a.id from public.aircraft a
     where a.world_id = w
       and a.registration in (select p.key from pg_temp.t_pa p where p.section in ('tails', 'deliveries') and p.state = 'changed')
       and not exists (select 1 from pg_temp.t_pa p where p.section in ('tails', 'deliveries') and p.key = a.registration and p.eff_item is not null);
    update public.aircraft a set status = 'retired', retired_on = coalesce(a.retired_on, current_date),
           extra = a.extra - array['tails_index', 'deliveries_index', 'tail', 'delivery']
     where a.id in (select id from pg_temp.t_pa_gone) and a.status <> 'retired'
       and (exists (select 1 from public.game_flights f where f.aircraft_id = a.id)
            or exists (select 1 from public.game_payments p where p.aircraft_id = a.id)
            or exists (select 1 from public.spending_log x where x.aircraft_id = a.id));
    get diagnostics n = row_count; v_out := v_out || jsonb_build_object('aircraft retired', n);
    delete from public.aircraft a
     where a.id in (select id from pg_temp.t_pa_gone) and a.status <> 'retired'
       and not exists (select 1 from public.flight_legs l where l.aircraft_id = a.id)
       and not exists (select 1 from public.plan_cards p where p.aircraft_id = a.id)
       and not exists (select 1 from public.aircraft_cabin_keeps k where k.aircraft_id = a.id);
    get diagnostics n = row_count; v_out := v_out || jsonb_build_object('aircraft removed', n);
    update public.aircraft a set extra = a.extra - array['tails_index', 'deliveries_index', 'tail', 'delivery']
     where a.id in (select id from pg_temp.t_pa_gone) and a.extra ?| array['tails_index', 'deliveries_index', 'tail', 'delivery'];
  end if;

  if to_regclass('pg_temp.t_pa_routes') is not null then
    delete from public.routes x using pg_temp.t_pa_routes r
     where x.airline_id = r.airline_id and x.hub_code = r.hub and x.dest_code = r.dest
       and r.checked and r.research is null and r.added is null and r.edit is null and r.cabin is null
       and not exists (select 1 from pg_temp.t_pa p where p.section in ('freqs', 'farePlan') and p.eff_item ->> 'routeKey' = r.key)
       and not exists (select 1 from public.rotations o where o.route_id = x.id)
       and not exists (select 1 from public.fare_plan o where o.route_id = x.id)
       and not exists (select 1 from public.game_flights o where o.route_id = x.id);
    get diagnostics n = row_count; v_out := v_out || jsonb_build_object('routes removed', n);
  end if;

  if exists (select 1 from pg_temp.t_pa where section like 'ref.%' and state = 'changed' and new_item is null) then
    delete from public.markets x using pg_temp.t_pa p, public.airlines al
     where p.section = 'ref.markets' and p.state = 'changed' and p.new_item is null
       and al.world_id = w and al.planner_name = split_part(p.key, '|', 1)
       and x.airline_id = al.id and x.name = substr(p.key, strpos(p.key, '|') + 1)
       and not exists (select 1 from public.routes o where o.market_id = x.id or o.market_override_id = x.id);
    delete from public.cabin_configs x using pg_temp.t_pa p
     where p.section = 'ref.configs' and p.state = 'changed' and p.new_item is null and x.world_id = w and x.code = p.key
       and not exists (select 1 from public.aircraft o where o.cabin_config_id = x.id or o.order_config_id = x.id)
       and not exists (select 1 from public.markets o where o.default_config_id = x.id);
    delete from public.aircraft_types x using pg_temp.t_pa p
     where p.section = 'ref.types' and p.state = 'changed' and p.new_item is null and x.world_id = w and x.name = p.key
       and not exists (select 1 from public.aircraft o where o.aircraft_type_id = x.id)
       and not exists (select 1 from public.cabin_configs o where o.aircraft_type_id = x.id)
       and not exists (select 1 from public.markets o where o.default_type_id = x.id)
       and not exists (select 1 from public.airline_aircraft_types o where o.aircraft_type_id = x.id);
    delete from public.service_profiles x using pg_temp.t_pa p
     where p.section = 'ref.services' and p.state = 'changed' and p.new_item is null and x.world_id = w and x.code = p.key;
  end if;
  return v_out;
end
$function$;

-- What the columns can't give back exactly (the loader's last step, for the items just written): the document is built
-- again, each written tail, delivery, frequency, plan card, to-do and fare plan is compared with what was saved, and any
-- key that differs (beyond the differences design §9 allows) is kept in the row's extra as saved, or as null where the
-- saved item has no such key. Returns the document as the tables now give it.
create or replace function private.planner_apply_extra(p_world_id bigint)
 returns jsonb
 language plpgsql
 set search_path to ''
as $function$
declare w bigint := p_world_id; g jsonb; n int;
begin
  g := (public.planner_state_get(w) ->> 'json')::jsonb;
  if not exists (select 1 from pg_temp.t_pa where state = 'changed' and new_item is not null
                    and section in ('tails', 'deliveries', 'freqs', 'plans', 'todos', 'farePlan')) then
    return g;
  end if;
  if to_regclass('pg_temp.t_pa_patch') is null then
    create temporary table t_pa_patch (section text, item_key text, key text, value jsonb) on commit drop;
  end if;
  truncate pg_temp.t_pa_patch;
  with written as (
    select p.section, p.key, p.new_item,
           case when p.section = 'plans' then '$.plans.' || p.key else '$.' || p.section || '[' || p.new_pos || ']' end as prefix
      from pg_temp.t_pa p
     where p.state = 'changed' and p.new_item is not null and p.section in ('tails', 'deliveries', 'freqs', 'plans', 'todos', 'farePlan')),
  built as (select b.section, b.key, b.item from private.planner_items(g) b
             where b.section in ('tails', 'deliveries', 'freqs', 'plans', 'todos', 'farePlan')),
  keys as (
    select distinct x.section, x.key, x.new_item, (regexp_match(substr(df.path, length(x.prefix) + 2), '^([^.\[]+)'))[1] as k
      from written x join built b on b.section = x.section and b.key = x.key
      cross join lateral private.planner_json_diff(x.new_item, b.item, x.prefix) df
     where df.kind = 'differs' and length(df.path) > length(x.prefix))
  insert into pg_temp.t_pa_patch
  select k.section, k.key, k.k, coalesce(k.new_item -> k.k, 'null'::jsonb) from keys k where k.k is not null;
  get diagnostics n = row_count;
  if n = 0 then return g; end if;
  update public.rotations r set extra = r.extra || p.patch
    from (select item_key, jsonb_object_agg(key, value) as patch from pg_temp.t_pa_patch where section = 'freqs' group by item_key) p
   where r.world_id = w and r.legacy_key = p.item_key and (r.extra || p.patch) is distinct from r.extra;
  update public.todos t set extra = t.extra || p.patch
    from (select item_key, jsonb_object_agg(key, value) as patch from pg_temp.t_pa_patch where section = 'todos' group by item_key) p
   where t.world_id = w and t.legacy_key = p.item_key and (t.extra || p.patch) is distinct from t.extra;
  update public.fare_plan t set extra = t.extra || p.patch
    from (select item_key, jsonb_object_agg(key, value) as patch from pg_temp.t_pa_patch where section = 'farePlan' group by item_key) p
   where t.world_id = w and t.legacy_key = p.item_key and (t.extra || p.patch) is distinct from t.extra;
  update public.plan_cards t set extra = t.extra || p.patch
    from (select item_key, jsonb_object_agg(key, value) as patch from pg_temp.t_pa_patch where section = 'plans' group by item_key) p,
         public.aircraft a
   where t.world_id = w and a.id = t.aircraft_id and a.registration = p.item_key and (t.extra || p.patch) is distinct from t.extra;
  update public.aircraft a set extra = jsonb_set(a.extra, '{tail}', coalesce(a.extra -> 'tail', '{}'::jsonb) || p.patch)
    from (select item_key, jsonb_object_agg(key, value) as patch from pg_temp.t_pa_patch where section = 'tails' group by item_key) p
   where a.world_id = w and a.registration = p.item_key and (coalesce(a.extra -> 'tail', '{}'::jsonb) || p.patch) is distinct from a.extra -> 'tail';
  update public.aircraft a set extra = jsonb_set(a.extra, '{delivery}', coalesce(a.extra -> 'delivery', '{}'::jsonb) || p.patch)
    from (select item_key, jsonb_object_agg(key, value) as patch from pg_temp.t_pa_patch where section = 'deliveries' group by item_key) p
   where a.world_id = w and a.registration = p.item_key and (coalesce(a.extra -> 'delivery', '{}'::jsonb) || p.patch) is distinct from a.extra -> 'delivery';
  return (public.planner_state_get(w) ->> 'json')::jsonb;
end
$function$;

-- Saves a planner document into a world's tables (design §8), writing only the rows of the items that differ:
--   1. a lock for the world (pg_advisory_xact_lock), so saves queue instead of racing;
--   2. the document and the tables (planner_state_get()) as items; an item differs when the two aren't the same within
--      the differences design §9 allows;
--   3. mode 'save' (planner_state_put): an item that differs and that someone else changed after p_base (another actor,
--      or another tab than p_client) is skipped, so a newer change is never overwritten (§11, choice 4). Mode 'mirror'
--      (the side-by-side trigger, the old row being the truth) and 'item' (planner_item_put) skip nothing;
--   4. the rest is written, named as p_actor with p_detail for the change log (left as the caller set it when p_actor is
--      null), then what the columns can't give back goes to extra.
-- Returns {applied, skipped, skipped_items, rows, doc}: how many items were written and skipped, which were skipped
-- ("section key"), the rows each step wrote, and the document as the tables now give it.
create or replace function private.planner_apply(p_world_id bigint, p_doc jsonb, p_mode text, p_base timestamptz,
                                                 p_client text, p_actor text, p_detail text)
 returns jsonb
 language plpgsql
 set search_path to ''
as $function$
declare w bigint := p_world_id; v_cur jsonb; v_doc jsonb; v_rows jsonb := '{}'::jsonb; v_applied int; v_skipped int;
  v_skipped_items jsonb;
  v_actor text := current_setting('equinox.actor', true); v_detail text := current_setting('equinox.actor_detail', true);
begin
  if p_mode not in ('save', 'mirror', 'item') then raise exception 'planner_apply: unknown mode %', p_mode; end if;
  if jsonb_typeof(p_doc) is distinct from 'object' then raise exception 'planner_apply: the document isn''t a JSON object'; end if;
  perform pg_advisory_xact_lock(hashtextextended('equinox planner world', w));
  v_cur := (public.planner_state_get(w) ->> 'json')::jsonb;

  if to_regclass('pg_temp.t_pa') is null then
    create temporary table t_pa (section text, key text, grp text, new_pos int, cur_pos int, new_item jsonb,
      cur_item jsonb, state text, eff_item jsonb, primary key (section, key)) on commit drop;
  end if;
  truncate pg_temp.t_pa;
  -- eff_item: the document's item, or the tables' where the document has none of an unchanged item (an item that is
  -- skipped below keeps the tables')
  insert into pg_temp.t_pa (section, key, grp, new_pos, cur_pos, new_item, cur_item, state, eff_item)
  select coalesce(n.section, c.section), coalesce(n.key, c.key), coalesce(n.grp, c.grp), n.pos, c.pos, n.item, c.item,
         case when n.item is null or c.item is null then 'changed'
              when n.item = c.item then 'same'
              when exists (select 1 from private.planner_json_diff(n.item, c.item,
                             case when n.section = 'tails' then '$.tails[' || n.pos || ']' else '$' end) d
                            where d.kind = 'differs') then 'changed'
              else 'same' end,
         n.item
    from private.planner_items(p_doc) n
    full join private.planner_items(v_cur) c on c.section = n.section and c.key = n.key;

  if p_mode = 'save' then
    update pg_temp.t_pa p set state = 'skipped', eff_item = p.cur_item
      from (select distinct t.section, t.key from private.planner_touched(w, coalesce(p_base, now()), p_client) t) t
     where p.state = 'changed' and p.section = t.section and p.grp = t.key;
  end if;
  select count(*) filter (where state = 'changed'), count(*) filter (where state = 'skipped'),
         coalesce(jsonb_agg(section || ' ' || key order by section, key) filter (where state = 'skipped'), '[]'::jsonb)
    into v_applied, v_skipped, v_skipped_items
    from pg_temp.t_pa;
  if v_applied = 0 then
    return jsonb_build_object('applied', 0, 'skipped', v_skipped, 'skipped_items', v_skipped_items, 'rows', v_rows, 'doc', v_cur);
  end if;

  if p_actor is not null then
    perform set_config('equinox.actor', p_actor, true), set_config('equinox.actor_detail', coalesce(p_detail, ''), true);
  end if;
  v_rows := v_rows || private.planner_apply_places(w);
  v_rows := v_rows || private.planner_apply_reference(w);
  v_rows := v_rows || private.planner_apply_routes(w);
  v_rows := v_rows || private.planner_apply_fleet(w);
  v_rows := v_rows || private.planner_apply_flights(w);
  v_rows := v_rows || private.planner_apply_work(w, v_skipped = 0);
  v_rows := v_rows || private.planner_apply_money(w);
  v_rows := v_rows || private.planner_apply_tidy(w);
  v_doc := private.planner_apply_extra(w);
  if p_actor is not null then
    perform set_config('equinox.actor', coalesce(v_actor, ''), true), set_config('equinox.actor_detail', coalesce(v_detail, ''), true);
  end if;
  return jsonb_build_object('applied', v_applied, 'skipped', v_skipped, 'skipped_items', v_skipped_items,
                            'rows', (select coalesce(jsonb_object_agg(e.key, e.value), '{}'::jsonb) from jsonb_each(v_rows) e where e.value <> '0'::jsonb),
                            'doc', v_doc);
end
$function$;

-- A planner document with one item set, or removed (p_value null), in today's JSON shape (for planner_item_put and
-- planner_item_delete). Sections and keys as private.planner_items() has them: plans, routeEdits, routeCabin,
-- interline, dismissed, cabinKeep, cash and fixed7 by their key (cash and fixed7: a date, valued {airline: millions});
-- monthly by airline (valued {task: date}); tails, deliveries, freqs, todos and farePlan by id; routesAdded by
-- "Airline|HUB|DEST"; ref.hubs by "Airline|CODE", ref.types by name, ref.configs and ref.services by code (set in place,
-- or added at the end); ref.markets, ref.curfews, ref.utcOverrides, ref.gameLinks and ref.consts by their key;
-- ref.timeMode alone; capex and growthLog by place in the list (0 first; no key adds at the end).
create or replace function private.planner_doc_with_item(p_doc jsonb, p_section text, p_key text, p_value jsonb)
 returns jsonb
 language plpgsql
 immutable
 set search_path to ''
as $function$
declare v_path text[]; v_list jsonb; v_id text; v_out jsonb := '[]'::jsonb; e jsonb; v_done boolean := false; i int;
begin
  if p_value = 'null'::jsonb then p_value := null; end if;
  if p_section in ('plans', 'routeEdits', 'routeCabin', 'interline', 'dismissed', 'cabinKeep', 'monthly', 'cash', 'fixed7',
                   'ref.markets', 'ref.curfews', 'ref.utcOverrides', 'ref.gameLinks', 'ref.consts') then
    if coalesce(p_key, '') = '' then raise exception '% needs a key', p_section; end if;
    v_path := case when p_section like 'ref.%' then array['ref', substr(p_section, 5)] else array[p_section] end;
    v_list := case when jsonb_typeof(p_doc #> v_path) = 'object' then p_doc #> v_path else '{}'::jsonb end;
    v_list := case when p_value is null then v_list - p_key else v_list || jsonb_build_object(p_key, p_value) end;
  elsif p_section = 'ref.timeMode' then
    return case when p_value is null then jsonb_set(p_doc, '{ref}', coalesce(p_doc -> 'ref', '{}'::jsonb) - 'timeMode')
                else jsonb_set(p_doc, '{ref}', coalesce(p_doc -> 'ref', '{}'::jsonb) || jsonb_build_object('timeMode', p_value)) end;
  elsif p_section in ('tails', 'deliveries', 'freqs', 'todos', 'farePlan', 'routesAdded', 'ref.hubs', 'ref.types', 'ref.configs', 'ref.services') then
    if coalesce(p_key, '') = '' then raise exception '% needs a key', p_section; end if;
    v_path := case when p_section like 'ref.%' then array['ref', substr(p_section, 5)] else array[p_section] end;
    v_id := case p_section when 'deliveries' then 'reg' when 'ref.types' then 'name' when 'ref.configs' then 'code'
                           when 'ref.services' then 'code' else 'id' end;
    if p_value is not null then
      if p_section = 'routesAdded' then
        if jsonb_typeof(p_value) <> 'array' or (p_value ->> 0) || '|' || (p_value ->> 1) || '|' || (p_value ->> 2) is distinct from p_key then
          raise exception 'a route added is [airline, hub, destination, ...] and its key airline|hub|destination';
        end if;
      elsif jsonb_typeof(p_value) <> 'object' then
        raise exception 'an item of % is a JSON object', p_section;
      elsif p_section = 'ref.hubs' then
        if (p_value ->> 'airline') || '|' || (p_value ->> 'code') is distinct from p_key then
          raise exception 'a hub''s key is its airline|code';
        end if;
      else
        p_value := p_value || jsonb_build_object(v_id, p_key);
      end if;
    end if;
    for e in select x from jsonb_array_elements(case when jsonb_typeof(p_doc #> v_path) = 'array' then p_doc #> v_path else '[]'::jsonb end) as x loop
      if (case when p_section = 'routesAdded' and jsonb_typeof(e) = 'array' then (e ->> 0) || '|' || (e ->> 1) || '|' || (e ->> 2)
               when p_section = 'ref.hubs' and jsonb_typeof(e) = 'object' then (e ->> 'airline') || '|' || (e ->> 'code')
               when jsonb_typeof(e) = 'object' then e ->> v_id end) is not distinct from p_key then
        if not v_done and p_value is not null then v_out := v_out || jsonb_build_array(p_value); end if;
        v_done := true;
      else
        v_out := v_out || jsonb_build_array(e);
      end if;
    end loop;
    if not v_done and p_value is not null then v_out := v_out || jsonb_build_array(p_value); end if;
    v_list := v_out;
  elsif p_section in ('capex', 'growthLog') then
    v_path := array[p_section];
    v_list := case when jsonb_typeof(p_doc -> p_section) = 'array' then p_doc -> p_section else '[]'::jsonb end;
    if p_value is not null and jsonb_typeof(p_value) <> 'object' then raise exception 'an entry of % is a JSON object', p_section; end if;
    if coalesce(p_key, '') = '' then
      if p_value is null then raise exception 'say which entry of % to remove: its place, 0 first', p_section; end if;
      v_list := v_list || jsonb_build_array(p_value);
    else
      if p_key !~ '^\d+$' or p_key::int >= jsonb_array_length(v_list) then
        raise exception '% has no entry %', p_section, p_key;
      end if;
      i := p_key::int;
      v_list := case when p_value is null then v_list - i else jsonb_set(v_list, array[i::text], p_value) end;
    end if;
  else
    raise exception 'unknown section: %', p_section;
  end if;
  if v_path[1] = 'ref' then
    return jsonb_set(p_doc, '{ref}', coalesce(case when jsonb_typeof(p_doc -> 'ref') = 'object' then p_doc -> 'ref' end, '{}'::jsonb)
                                     || jsonb_build_object(v_path[2], v_list));
  end if;
  return p_doc || jsonb_build_object(v_path[1], v_list);
end
$function$;

-- Who may save: planner staff (their sign-in), or postgres itself (Claude, the jobs, migrations), the way the getters
-- decide. Used by the functions below, which run as owner.
create or replace function private.caller_is_staff()
 returns boolean
 language sql
 stable
 set search_path to ''
as $function$
  select public.is_planner_user()
      or (session_user = 'postgres' and coalesce(nullif(current_setting('role', true), 'none'), session_user) = 'postgres')
$function$;

-- ============================================================ 4. loads (design §8)
-- Makes the tables give back the given loads days as planner_loads has them: for each day (a date key, valued as a day of
-- a planner_loads month), each flight whose economy load the getter shows differently becomes a load_entries row
-- (stamped p_at, so it wins over earlier captures; null where the day doesn't have the flight, which clears it), and a
-- day whose done or savedAt differs becomes a load_days row. Days the document doesn't have are left alone.
create or replace function private.loads_mirror_days(p_world_id bigint, p_days jsonb, p_at timestamptz)
 returns jsonb
 language plpgsql
 set search_path to ''
as $function$
declare w bigint := p_world_id; n int; m int;
begin
  if jsonb_typeof(p_days) is distinct from 'object' or p_days = '{}'::jsonb then
    return jsonb_build_object('load_entries', 0, 'load_days', 0);
  end if;
  if to_regclass('pg_temp.t_lm_days') is null then
    create temporary table t_lm_days (day date primary key, v jsonb, got jsonb) on commit drop;
  end if;
  truncate pg_temp.t_lm_days;
  insert into pg_temp.t_lm_days (day, v)
  select private.json_date(to_jsonb(e.key)), e.value from jsonb_each(p_days) e
   where private.json_date(to_jsonb(e.key)) is not null and jsonb_typeof(e.value) = 'object'
  on conflict (day) do nothing;
  update pg_temp.t_lm_days t set got = g.v
    from (select d.key::date as day, d.value as v
            from public.planner_loads_get(w) pl cross join lateral jsonb_each(pl.json::jsonb) d
           where pl.month in (select distinct to_char(x.day, 'YYYY-MM') from pg_temp.t_lm_days x)) g
   where g.day = t.day;

  with ours as (
    select a.id, a.planner_name from public.airlines a
      join public.groups g on g.id = a.group_id and g.world_id = a.world_id
     where a.world_id = w and g.kind = 'ours'),
  tf as (select t.day, f.key, f.value from pg_temp.t_lm_days t
           cross join lateral jsonb_each(case when jsonb_typeof(t.v -> 'f') = 'object' then t.v -> 'f' else '{}'::jsonb end) f),
  gf as (select t.day, f.key, f.value from pg_temp.t_lm_days t
           cross join lateral jsonb_each(case when jsonb_typeof(t.got -> 'f') = 'object' then t.got -> 'f' else '{}'::jsonb end) f),
  fd as (select coalesce(tf.day, gf.day) as day, coalesce(tf.key, gf.key) as k, tf.value as tv
           from tf full join gf on gf.day = tf.day and gf.key = tf.key
          where tf.value is distinct from gf.value)
  insert into public.load_entries as x (world_id, airline_id, game_date, flight_no, eco_pct, entered_at)
  select w, o.id, fd.day, private.json_int(to_jsonb(split_part(fd.k, '|', 2))),
         (select v from private.json_num(fd.tv) v where abs(v) < 10000), p_at
    from fd join ours o on o.planner_name = split_part(fd.k, '|', 1)
   where private.json_int(to_jsonb(split_part(fd.k, '|', 2))) between 0 and 2000000000
  on conflict (airline_id, game_date, flight_no) do update set eco_pct = excluded.eco_pct, entered_at = excluded.entered_at
  where (x.eco_pct, x.entered_at) is distinct from (excluded.eco_pct, excluded.entered_at);
  get diagnostics n = row_count;

  -- a day whose flags the getter shows differently: stamped again even when the row already says the same, since a
  -- capture since then is what makes the getter differ (it counts the day complete once every airline has flown it,
  -- while the capture's loads step waits for all of the capture day's pages)
  insert into public.load_days as x (world_id, game_date, done, saved_at_ms, entered_at)
  select w, t.day, coalesce(t.v -> 'done' = 'true'::jsonb, false), private.json_int(t.v -> 'savedAt'), p_at
    from pg_temp.t_lm_days t
   where coalesce(t.v -> 'done', 'false'::jsonb) is distinct from coalesce(t.got -> 'done', 'false'::jsonb)
      or (t.v -> 'savedAt') is distinct from (t.got -> 'savedAt')
  on conflict (world_id, game_date) do update set done = excluded.done, saved_at_ms = excluded.saved_at_ms,
    entered_at = excluded.entered_at
  where (x.done, x.saved_at_ms, x.entered_at) is distinct from (excluded.done, excluded.saved_at_ms, excluded.entered_at);
  get diagnostics m = row_count;
  return jsonb_build_object('load_entries', n, 'load_days', m);
end
$function$;

-- save_loads(): the same name, arguments, answer and planner_loads writes as before (migration 20261009120000). It also
-- writes the days it saved to load_entries and load_days (design §8), as actor planner, detail save_loads. While the
-- old storage is the truth (pull requests 5 to 9) a failure there is recorded in job_runs and never stops the save.
create or replace function public.save_loads(p_month text, p_days jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare cur jsonb; d text; p jsonb; day jsonb; f jsonb; v_days jsonb := '{}'::jsonb; w bigint;
  ms bigint := (extract(epoch from clock_timestamp()) * 1000)::bigint;
  v_actor text := current_setting('equinox.actor', true); v_detail text := current_setting('equinox.actor_detail', true);
begin
  if not public.is_planner_user() then raise exception 'only planner staff can save loads' using errcode = '42501'; end if;
  if p_month is null or p_month !~ '^\d{4}-\d{2}$' then raise exception 'month must be YYYY-MM, got %', p_month; end if;
  if jsonb_typeof(p_days) is distinct from 'object' then raise exception 'days must be an object keyed by date'; end if;
  insert into public.planner_loads (month, json, saved_at) values (p_month, '{}', 0) on conflict (month) do nothing;
  select pl.json::jsonb into cur from public.planner_loads pl where pl.month = p_month for update;
  cur := coalesce(cur, '{}'::jsonb) - '__savedAt';   -- a browser-only marker that older saves wrote into the document
  for d, p in select e.key, e.value from jsonb_each(p_days) e loop
    if d !~ ('^' || p_month || '-\d{2}$') then raise exception 'day % is not in month %', d, p_month; end if;
    if jsonb_typeof(p) is distinct from 'object' then raise exception 'day % must be an object', d; end if;
    day := coalesce(cur -> d, '{"done": false, "f": {}}'::jsonb);
    if p ? 'f' then
      f := coalesce(p -> 'f', '{}'::jsonb);                                          -- the whole day's entry, as typed
    else
      f := (coalesce(day -> 'f', '{}'::jsonb) || coalesce(p -> 'set', '{}'::jsonb))   -- single flights: set these ...
           - array(select jsonb_array_elements_text(coalesce(p -> 'del', '[]'::jsonb)));   -- ... and clear these
    end if;
    day := jsonb_set(day, '{f}', f, true);
    if p ? 'done' then day := day || jsonb_build_object('done', p -> 'done'); end if;
    if p ? 'savedAt' then day := day || jsonb_build_object('savedAt', p -> 'savedAt'); end if;
    cur := jsonb_set(cur, array[d], day, true);
    v_days := v_days || jsonb_build_object(d, day);
  end loop;
  select x.id into w from public.worlds x where x.is_default;
  begin
    perform set_config('equinox.actor', 'planner', true), set_config('equinox.actor_detail', 'save_loads', true);
    perform private.loads_mirror_days(w, v_days, now());
    perform set_config('equinox.actor', coalesce(v_actor, ''), true), set_config('equinox.actor_detail', coalesce(v_detail, ''), true);
  exception when others then
    perform private.job_run_add('adapter_mirror', w, clock_timestamp(), 'failed', 'save_loads: ' || sqlerrm,
                                jsonb_build_object('table', 'planner_loads', 'month', p_month, 'sqlstate', sqlstate));
  end;
  update public.planner_loads set json = cur::text, saved_at = ms where month = p_month;
  return jsonb_build_object('month', p_month, 'json', cur, 'saved_at', ms);
end
$function$;

-- ============================================================ 5. the adapter's write functions (design §8)
-- Saves the planner's document into the tables, writing only the rows that changed. A row someone else changed after
-- p_base (another actor, or another tab than p_client) is skipped, and the answer asks the tab to reload (§11, choice
-- 4); with no base, the save's own time p_saved_at is used. Written as actor planner, the tab in actor_detail. Answers
-- {saved_at, applied, skipped, reload, skipped_items}: the time to keep for the next save (server time,
-- planner_state_version()), how many items were written and skipped, and which ("section key"). Staff only; runs as
-- owner, since its steps are in private, and checks the caller itself. Not called by the planner yet: pull request 9.
create or replace function public.planner_state_put(p_json text, p_saved_at bigint, p_base bigint, p_client text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare w bigint; v_doc jsonb; v_res jsonb;
begin
  if not private.caller_is_staff() then raise exception 'only planner staff can save the planner' using errcode = '42501'; end if;
  begin
    v_doc := p_json::jsonb;
  exception when others then
    raise exception 'the planner document isn''t JSON' using errcode = '22023';
  end;
  if jsonb_typeof(v_doc) is distinct from 'object' then raise exception 'the planner document isn''t a JSON object' using errcode = '22023'; end if;
  select x.id into w from public.worlds x where x.is_default;
  v_res := private.planner_apply(w, v_doc, 'save', to_timestamp(coalesce(p_base, p_saved_at) / 1000.0), nullif(p_client, ''),
                                 'planner', nullif(p_client, ''));
  return jsonb_build_object('saved_at', public.planner_state_version(w), 'applied', v_res -> 'applied',
                            'skipped', v_res -> 'skipped', 'reload', (v_res ->> 'skipped')::int > 0,
                            'skipped_items', v_res -> 'skipped_items');
end
$function$;

-- One item of the planner's document, in today's JSON shape, set through the same code as a save (for other chats'
-- data-only changes: a plan card, a to-do, a frequency ...). Sections and keys: see private.planner_doc_with_item().
-- Plan-card and frequency times are local, as the planner has them, and stored in UTC. The change log names whoever
-- the caller set (equinox.actor), or planner for a signed-in user. Staff and postgres only; runs as owner.
create or replace function public.planner_item_put(p_section text, p_key text, p_value jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare w bigint; v_res jsonb;
begin
  if not private.caller_is_staff() then raise exception 'only planner staff can save the planner' using errcode = '42501'; end if;
  if p_value is null or p_value = 'null'::jsonb then
    raise exception 'planner_item_put needs a value: planner_item_delete removes an item' using errcode = '22023';
  end if;
  select x.id into w from public.worlds x where x.is_default;
  perform pg_advisory_xact_lock(hashtextextended('equinox planner world', w));
  v_res := private.planner_apply(w, private.planner_doc_with_item((public.planner_state_get(w) ->> 'json')::jsonb, p_section, p_key, p_value),
                                 'item', null, null, null, null);
  return jsonb_build_object('saved_at', public.planner_state_version(w), 'applied', v_res -> 'applied', 'skipped', 0, 'reload', false);
end
$function$;

-- Removes one item of the planner's document through the same code as a save. As planner_item_put().
create or replace function public.planner_item_delete(p_section text, p_key text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare w bigint; v_res jsonb;
begin
  if not private.caller_is_staff() then raise exception 'only planner staff can save the planner' using errcode = '42501'; end if;
  select x.id into w from public.worlds x where x.is_default;
  perform pg_advisory_xact_lock(hashtextextended('equinox planner world', w));
  v_res := private.planner_apply(w, private.planner_doc_with_item((public.planner_state_get(w) ->> 'json')::jsonb, p_section, p_key, null),
                                 'item', null, null, null, null);
  return jsonb_build_object('saved_at', public.planner_state_version(w), 'applied', v_res -> 'applied', 'skipped', 0, 'reload', false);
end
$function$;

-- ============================================================ 6. side by side on live (design §9)
-- Whether this version of an old row was already copied and compared in this transaction (and marks it so). The
-- side-by-side triggers run when the transaction commits, once per write, and all the writes of one transaction see
-- the same last version: the first does the work. A version is the row's place on disk, which changes with each write.
create or replace function private.adapter_seen(p_key text)
 returns boolean
 language plpgsql
 set search_path to ''
as $function$
declare v_seen text := coalesce(current_setting('equinox.adapter_seen', true), '');
begin
  if position('|' || p_key || '|' in v_seen) > 0 then return true; end if;
  perform set_config('equinox.adapter_seen', v_seen || '|' || p_key || '|', true);
  return false;
end
$function$;

-- After every save of planner_state (the old planner, or Claude by hand), when the transaction commits: the row as it
-- then stands is copied into the tables in mirror mode (actor planner, detail mirror; no skipping, the old row is the
-- truth), then planner_state_get() is compared with it, with exactly the differences the tests allow
-- (private.planner_state_check). Each is one job_runs row: ok, or failed with where it differed in note and the paths in
-- details. Every error is caught and recorded: the save itself always goes through. Runs as owner so it can write
-- job_runs, which stays read-only to everyone else.
create or replace function private.adapter_mirror_state()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare w bigint; t0 timestamptz := clock_timestamp(); t1 timestamptz; v_doc jsonb; v_res jsonb; v_got jsonb;
  v_n int; v_note text; v_details jsonb; v_json text; v_saved bigint; v_ver text;
begin
  if new.id is distinct from 'main' then return null; end if;
  select p.json, p.saved_at, p.ctid::text into v_json, v_saved, v_ver from public.planner_state p where p.id = 'main';
  if not found or private.adapter_seen('planner_state ' || v_ver) then return null; end if;
  begin
    select x.id into w from public.worlds x where x.is_default;
    begin
      v_doc := v_json::jsonb;
      if jsonb_typeof(v_doc) is distinct from 'object' then raise exception 'planner_state.json isn''t a JSON object'; end if;
      v_res := private.planner_apply(w, v_doc, 'mirror', null, null, 'planner', 'mirror');
      perform private.job_run_add('adapter_mirror', w, t0, 'ok',
        case when (v_res ->> 'applied')::int = 0 then 'planner_state: nothing to copy'
             else 'planner_state: copied ' || (v_res ->> 'applied') || ' item(s)' end,
        jsonb_build_object('table', 'planner_state', 'items', (v_res ->> 'applied')::int, 'rows', v_res -> 'rows',
                           'ms', round(extract(epoch from clock_timestamp() - t0) * 1000)));
    exception when others then
      v_res := null;
      perform private.job_run_add('adapter_mirror', w, t0, 'failed', 'planner_state: ' || sqlerrm,
                                  jsonb_build_object('table', 'planner_state', 'sqlstate', sqlstate));
    end;
    t1 := clock_timestamp();
    begin
      v_got := coalesce(v_res -> 'doc', (public.planner_state_get(w) ->> 'json')::jsonb);
      with c as (select * from private.planner_state_check(w, v_doc, v_saved, v_got))
      select count(*) filter (where c.kind = 'differs'),
             (select string_agg(z.place || ' ×' || z.n, ', ' order by z.place)
                from (select private.planner_place(c2.path) as place, count(*) as n from c c2 where c2.kind = 'differs' group by 1) z),
             jsonb_build_object('table', 'planner_state', 'saved_at', v_saved,
               'paths', coalesce((select jsonb_agg(z.path order by z.path) from (select c2.path from c c2 where c2.kind = 'differs' order by c2.path limit 200) z), '[]'::jsonb),
               'cash', coalesce((select jsonb_agg(c2.why order by c2.path) from c c2 where c2.why is not null), '[]'::jsonb),
               'allowed', coalesce((select jsonb_object_agg(z.kind, z.n) from (select c2.kind, count(*) as n from c c2 where c2.kind <> 'differs' group by 1) z), '{}'::jsonb),
               'ms', round(extract(epoch from clock_timestamp() - t1) * 1000))
        into v_n, v_note, v_details
        from c;
      perform private.job_run_add('adapter_check', w, t1, case when v_n = 0 then 'ok' else 'failed' end,
        case when v_n = 0 then 'planner_state_get() equals planner_state' else 'planner_state differs at: ' || v_note end, v_details);
    exception when others then
      perform private.job_run_add('adapter_check', w, t1, 'failed', 'planner_state: the comparison stopped: ' || sqlerrm,
                                  jsonb_build_object('table', 'planner_state', 'sqlstate', sqlstate));
    end;
  exception when others then
    null;   -- nothing here may stop the save
  end;
  return null;
end
$function$;

-- After every write of planner_loads (save_loads() or the capture's loads step, which writes a month once per day),
-- when the transaction commits: the month's days as they then stand are copied into load_entries and load_days
-- (private.loads_mirror_days, actor planner, detail mirror), then planner_loads_get()'s month is compared with it, with
-- design §9's allowed differences. One job_runs row each, as for planner_state; never stops the write.
create or replace function private.adapter_mirror_loads()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare w bigint; t0 timestamptz := clock_timestamp(); t1 timestamptz; v_doc jsonb; v_res jsonb; v_got jsonb;
  v_n int; v_note text; v_details jsonb; v_json text; v_saved bigint; v_ver text;
  v_actor text := current_setting('equinox.actor', true); v_detail text := current_setting('equinox.actor_detail', true);
begin
  select p.json, p.saved_at, p.ctid::text into v_json, v_saved, v_ver from public.planner_loads p where p.month = new.month;
  if not found or private.adapter_seen('planner_loads ' || new.month || ' ' || v_ver) then return null; end if;
  begin
    select x.id into w from public.worlds x where x.is_default;
    begin
      v_doc := v_json::jsonb;
      if jsonb_typeof(v_doc) is distinct from 'object' then raise exception 'planner_loads.json isn''t a JSON object'; end if;
      perform set_config('equinox.actor', 'planner', true), set_config('equinox.actor_detail', 'mirror', true);
      v_res := private.loads_mirror_days(w, (select coalesce(jsonb_object_agg(e.key, e.value), '{}'::jsonb) from jsonb_each(v_doc) e
                                               where e.key like new.month || '-%'), now());
      perform set_config('equinox.actor', coalesce(v_actor, ''), true), set_config('equinox.actor_detail', coalesce(v_detail, ''), true);
      perform private.job_run_add('adapter_mirror', w, t0, 'ok',
        case when (v_res ->> 'load_entries')::int + (v_res ->> 'load_days')::int = 0 then 'planner_loads ' || new.month || ': nothing to copy'
             else 'planner_loads ' || new.month || ': copied ' || (v_res ->> 'load_entries') || ' load(s), ' || (v_res ->> 'load_days') || ' day flag(s)' end,
        jsonb_build_object('table', 'planner_loads', 'month', new.month, 'rows', v_res,
                           'ms', round(extract(epoch from clock_timestamp() - t0) * 1000)));
    exception when others then
      perform private.job_run_add('adapter_mirror', w, t0, 'failed', 'planner_loads ' || new.month || ': ' || sqlerrm,
                                  jsonb_build_object('table', 'planner_loads', 'month', new.month, 'sqlstate', sqlstate));
    end;
    t1 := clock_timestamp();
    begin
      select g.json::jsonb into v_got from public.planner_loads_get(w) g where g.month = new.month;
      with c as (select * from private.planner_json_diff(v_doc, coalesce(v_got, '{}'::jsonb)))
      select count(*) filter (where c.kind = 'differs'),
             (select string_agg(z.place || ' ×' || z.n, ', ' order by z.place)
                from (select private.planner_place(c2.path) as place, count(*) as n from c c2 where c2.kind = 'differs' group by 1) z),
             jsonb_build_object('table', 'planner_loads', 'month', new.month, 'saved_at', v_saved,
               'paths', coalesce((select jsonb_agg(z.path order by z.path) from (select c2.path from c c2 where c2.kind = 'differs' order by c2.path limit 200) z), '[]'::jsonb),
               'allowed', coalesce((select jsonb_object_agg(z.kind, z.n) from (select c2.kind, count(*) as n from c c2 where c2.kind <> 'differs' group by 1) z), '{}'::jsonb),
               'ms', round(extract(epoch from clock_timestamp() - t1) * 1000))
        into v_n, v_note, v_details
        from c;
      perform private.job_run_add('adapter_check', w, t1, case when v_n = 0 then 'ok' else 'failed' end,
        case when v_n = 0 then 'planner_loads_get() equals planner_loads ' || new.month
             else 'planner_loads ' || new.month || ' differs at: ' || v_note end, v_details);
    exception when others then
      perform private.job_run_add('adapter_check', w, t1, 'failed', 'planner_loads ' || new.month || ': the comparison stopped: ' || sqlerrm,
                                  jsonb_build_object('table', 'planner_loads', 'month', new.month, 'sqlstate', sqlstate));
    end;
  exception when others then
    null;   -- nothing here may stop the write
  end;
  return null;
end
$function$;

-- Per world and capture day (design §2), the side by side's runs: comparisons, failures, and whether the day is clean
-- (at least one comparison and nothing failed, mirror or comparison).
create view public.adapter_check_days with (security_invoker = true) as
select j.world_id, j.for_day as day,
       count(*) filter (where j.job = 'adapter_check') as comparisons,
       count(*) filter (where j.job = 'adapter_check' and j.status = 'failed') as comparisons_failed,
       count(*) filter (where j.job = 'adapter_mirror') as mirrors,
       count(*) filter (where j.job = 'adapter_mirror' and j.status = 'failed') as mirrors_failed,
       (count(*) filter (where j.job = 'adapter_check') > 0 and count(*) filter (where j.status = 'failed') = 0) as clean
  from public.job_runs j
 where j.job in ('adapter_mirror', 'adapter_check') and j.for_day is not null
 group by j.world_id, j.for_day;

-- How many clean days in a row (design §11, choice 1: the switch-over waits for 3), counted back from the capture day
-- p_as_of falls in (that day only once it has a run; a day still under way with none doesn't break the run). A day with
-- no comparison, or with any failure, ends the run. Pull request 9 reads it. Staff and postgres only.
create or replace function public.adapter_clean_days(p_world_id bigint default null, p_as_of timestamptz default now())
 returns integer
 language plpgsql
 stable
 security invoker
 set search_path to ''
as $function$
declare w bigint; v_day date; n int := 0;
begin
  if not (current_user = 'postgres' or public.is_planner_user()) then
    raise exception 'only planner staff can read the planner' using errcode = '42501';
  end if;
  select x.id into w from public.worlds x where x.id = p_world_id or (p_world_id is null and x.is_default);
  if w is null then raise exception 'no such world: %', p_world_id; end if;
  -- the capture day p_as_of falls in, as private.capture_day() works it out
  v_day := ((p_as_of at time zone 'UTC')
            - coalesce((select (s.value #>> '{}')::time from public.settings s
                         where s.world_id = w and s.airline_id is null and s.key = 'capture_day_starts_utc'), time '10:00')::interval)::date;
  if not exists (select 1 from public.adapter_check_days d where d.world_id = w and d.day = v_day) then
    v_day := v_day - 1;
  end if;
  while exists (select 1 from public.adapter_check_days d where d.world_id = w and d.day = v_day and d.clean) loop
    n := n + 1;
    v_day := v_day - 1;
  end loop;
  return n;
end
$function$;

-- ============================================================ 7. catch up, then side by side starts
-- The tables catch up with every save since pull request 4 (logged as migration, the change log off), and one
-- comparison of each old row is recorded, so the first job_runs rows say where things stand at the switch-on.
do $catchup$
declare w bigint := (select x.id from public.worlds x where x.is_default); t0 timestamptz; v_n int; v_note text; r record;
begin
  perform private.load_planner(w);
  begin
    t0 := clock_timestamp();
    with c as (select * from private.planner_state_check(w, (select p.json::jsonb from public.planner_state p where p.id = 'main'),
                                                          (select p.saved_at from public.planner_state p where p.id = 'main'),
                                                          (public.planner_state_get(w) ->> 'json')::jsonb))
    select count(*) filter (where c.kind = 'differs'), string_agg(distinct private.planner_place(c.path), ', ') filter (where c.kind = 'differs')
      into v_n, v_note from c;
    perform private.job_run_add('adapter_check', w, t0, case when v_n = 0 then 'ok' else 'failed' end,
      case when v_n = 0 then 'planner_state_get() equals planner_state (at the switch-on)' else 'planner_state differs at: ' || v_note || ' (at the switch-on)' end,
      jsonb_build_object('table', 'planner_state', 'migration', '20261010210000_adapter_write_side'));
    for r in select pl.month, pl.json from public.planner_loads pl order by pl.month loop
      t0 := clock_timestamp();
      select count(*) filter (where d.kind = 'differs'), string_agg(distinct private.planner_place(d.path), ', ') filter (where d.kind = 'differs')
        into v_n, v_note
        from private.planner_json_diff(private.json_object_or_empty(r.json),
                                       coalesce((select g.json::jsonb from public.planner_loads_get(w) g where g.month = r.month), '{}'::jsonb)) d;
      perform private.job_run_add('adapter_check', w, t0, case when v_n = 0 then 'ok' else 'failed' end,
        case when v_n = 0 then 'planner_loads_get() equals planner_loads ' || r.month || ' (at the switch-on)'
             else 'planner_loads ' || r.month || ' differs at: ' || v_note || ' (at the switch-on)' end,
        jsonb_build_object('table', 'planner_loads', 'month', r.month, 'migration', '20261010210000_adapter_write_side'));
    end loop;
  exception when others then
    perform private.job_run_add('adapter_check', w, clock_timestamp(), 'failed', 'the comparison at the switch-on stopped: ' || sqlerrm,
                                jsonb_build_object('migration', '20261010210000_adapter_write_side'));
  end;
end
$catchup$;

-- when each writing transaction commits (deferred), so a month the capture writes day by day is compared once, whole
create constraint trigger adapter_mirror after insert or update on public.planner_state
  deferrable initially deferred for each row execute function private.adapter_mirror_state();
create constraint trigger adapter_mirror after insert or update on public.planner_loads
  deferrable initially deferred for each row execute function private.adapter_mirror_loads();

-- ============================================================ 8. access (design §5)
-- job_runs and its view: staff read them, nobody else; only the side-by-side triggers (as owner) and postgres write.
-- The write functions: signed-in staff and postgres (they check the caller), nobody signed out. Internal steps closed.
revoke all on table public.job_runs, public.adapter_check_days from public, anon, authenticated;
grant select on table public.job_runs, public.adapter_check_days to authenticated;
revoke all on function public.planner_state_put(text, bigint, bigint, text), public.planner_item_put(text, text, jsonb),
  public.planner_item_delete(text, text), public.adapter_clean_days(bigint, timestamptz)
  from public, anon, authenticated;
grant execute on function public.planner_state_put(text, bigint, bigint, text), public.planner_item_put(text, text, jsonb),
  public.planner_item_delete(text, text), public.adapter_clean_days(bigint, timestamptz)
  to authenticated;
revoke all on function private.job_run_add(text, bigint, timestamptz, text, text, jsonb),
  private.planner_json_diff(jsonb, jsonb, text, text, boolean), private.planner_place(text),
  private.planner_state_check(bigint, jsonb, bigint, jsonb), private.capex_key(text, date, text, numeric, text),
  private.growth_key(text, date, text, text), private.planner_items(jsonb), private.planner_touched(bigint, timestamptz, text),
  private.planner_apply_places(bigint), private.planner_apply_reference(bigint), private.planner_apply_routes(bigint),
  private.planner_apply_fleet(bigint), private.planner_apply_flights(bigint), private.planner_apply_work(bigint, boolean),
  private.planner_apply_money(bigint), private.planner_apply_tidy(bigint), private.planner_apply_extra(bigint),
  private.planner_apply(bigint, jsonb, text, timestamptz, text, text, text), private.planner_doc_with_item(jsonb, text, text, jsonb),
  private.caller_is_staff(), private.loads_mirror_days(bigint, jsonb, timestamptz), private.adapter_seen(text),
  private.adapter_mirror_state(), private.adapter_mirror_loads()
  from public, anon, authenticated;

-- ============================================================ 9. descriptions (decision #10)
comment on table public.job_runs is 'One row per run of every job (design §3.11): when it started and finished, ok or failed, the day or month it was for, a note and the details. From #13''s pull request 5: adapter_mirror (a save of the old planner rows copied into the tables) and adapter_check (the getters compared with the row just saved). backup_runs moves in with pull request 7. Staff read it; only the database''s own functions and postgres write it. Not in the change log.';
comment on column public.job_runs.job is 'backup, snapshot, snapshot_fallback, cleanup, archive, adapter_mirror or adapter_check';
comment on column public.job_runs.world_id is 'The world it ran for, if any';
comment on column public.job_runs.status is 'running, ok, failed or incomplete';
comment on column public.job_runs.for_day is 'The day it was for: for the side by side, the capture day it ran in (design §2: 10:00 to 10:00 UTC)';
comment on column public.job_runs.for_month is 'The month it was for (its first day), e.g. an archive''s';
comment on column public.job_runs.note is 'What happened, in a line: for a failed comparison, where it differed (paths with list places as [] and keys as {})';
comment on column public.job_runs.details is 'What a job records about itself: for adapter_check the paths that differed (up to 200), why a cash or next-7-day figure wasn''t allowed, the allowed differences used and how long it took; for adapter_mirror the rows written';

comment on view public.adapter_check_days is 'Per world and capture day, the side by side''s runs (design §9): how many comparisons and mirrors, how many failed, and whether the day is clean (at least one comparison and nothing failed). adapter_clean_days() counts the clean days in a row. Shows the caller only what it may read.';
comment on column public.adapter_check_days.day is 'The capture day (design §2: 10:00 to 10:00 UTC)';
comment on column public.adapter_check_days.clean is 'At least one comparison, and no comparison or mirror failed';

comment on function public.adapter_clean_days(bigint, timestamp with time zone) is 'How many clean days in a row the side by side has had (design §11, choice 1: the switch-over waits for 3), counted back from the capture day p_as_of falls in (default now; that day counts once it has a run, and a day still under way with none doesn''t break the run). A day with no comparison, or with any failed mirror or comparison, ends the run. Pull request 9 reads it. Staff and postgres only.';
comment on function public.planner_state_put(text, bigint, bigint, text) is 'Saves the old planner''s document into the tables (design §8), writing only the rows that changed. Takes a lock per world; skips any item someone else (another actor, or another tab than p_client) changed after p_base, or after p_saved_at when there is no base (§11, choice 4); writes the rest as actor planner with the tab in actor_detail. Answers {saved_at (server time, planner_state_version()), applied, skipped, reload (true when anything was skipped), skipped_items}. Staff and postgres only; runs as owner and checks the caller itself. Not called by the planner yet: pull request 9 switches it over.';
comment on function public.planner_item_put(text, text, jsonb) is 'Sets one item of the planner''s document, in today''s JSON shape, through the same code as a save (design §8): for other chats'' data-only changes (a plan card, a to-do, a frequency ...). Section and key as private.planner_doc_with_item() describes; plan-card and frequency times are local, stored in UTC. The change log names whoever the caller set (equinox.actor), or planner for a signed-in user. Answers {saved_at, applied, skipped, reload}. Staff and postgres only; runs as owner and checks the caller itself.';
comment on function public.planner_item_delete(text, text) is 'Removes one item of the planner''s document through the same code as a save (design §8). As planner_item_put(). Staff and postgres only; runs as owner and checks the caller itself.';
comment on function public.save_loads(text, jsonb) is 'Saves the planner''s loads typed by hand: merges only the days given into the month''s planner_loads document (a whole day''s flights with f, or single flights with set and del, plus done and savedAt), so days captured since the page loaded aren''t lost, and returns the merged month (migration 20261009120000). Since #13''s pull request 5 it also writes those days to load_entries and load_days (actor planner, detail save_loads); a failure there is recorded in job_runs and never stops the save. Planner staff only; runs as owner.';

comment on function private.job_run_add(text, bigint, timestamp with time zone, text, text, jsonb) is 'Adds one finished job_runs row: the job, its world, when it started (and finished: now), ok or failed, the note and details; for_day is the capture day it started in.';
comment on function private.planner_json_diff(jsonb, jsonb, text, text, boolean) is 'private.planner_json_differences() with a shortcut: two equal values (numbers by value, keys in any order) are passed over without walking into them, so on a whole document it is many times faster. The only kind it can leave out is "numbers by value", which is allowed anyway: the differences that count are the same.';
comment on function private.planner_place(text) is 'Where a difference is, without the parts that change from item to item: list places as [], the keys of keyed sections as {}, a loads day as {day} and its flights as {flight}. For job_runs notes.';
comment on function private.planner_state_check(bigint, jsonb, bigint, jsonb) is 'A planner_state document against the one built from the tables, with exactly the differences the tests allow (planner_load_state_test.sql): design §9''s, plus "cash/fixed7 captured after the planner last saved", only where the built figure is the capture''s and that airline''s balance for the date (or, for fixed7, an event it counts) was captured after p_saved_at. One row per difference: its path, its kind (''differs'' when not allowed) and, for a money figure not allowed, why (dates and airlines only).';
comment on function private.capex_key(text, date, text, numeric, text) is 'What a money-spent entry says (airline, date, kind, amount in AS$, note) as one text, the same from the planner''s document and from a spending_log row: the entries have no id, so identical ones are interchangeable (design §8).';
comment on function private.growth_key(text, date, text, text) is 'What a growth move says (airline, date, move, note) as one text, the same from the planner''s document and from a growth_log row (design §8).';
comment on function private.planner_items(jsonb) is 'A planner document as items, the unit a save changes and a clash is decided on (design §8''s table): tails, deliveries, frequencies, to-dos and fare plans by id; plan cards, route edits, route cabins, interline, dismissed alerts and kept cabins by key; routes added by airline|hub|destination; monthly checks by airline|task; cash and next-7-day figures by date|airline; each ref list entry (hubs by airline|code, types by name, configs and services by code) and each key of ref''s maps; money spent and growth moves by what they say and which of the identical ones they are. With each item''s place in its list.';
comment on function private.planner_touched(bigint, timestamp with time zone, text) is 'The items someone else changed after a moment (design §8): every change_log row of the world since, except those this tab made (actor planner, detail p_client), traced back to the planner items it belongs to, under its old and new names. With no client, every later change counts.';
comment on function private.planner_apply_places(bigint) is 'Save step: the airports and countries the changed items name, by their code only, so nothing that names them is refused (as the loader does).';
comment on function private.planner_apply_reference(bigint) is 'Save step: ref''s types, cabin layouts, services, markets, constants (as settings, depCap as the house rule), time mode, hubs and focus cities, and what the world says about their airports (connection times, night bans, offsets), for the changed items only, with the loader''s rules. A type, layout or service renamed in place keeps its row.';
comment on function private.planner_apply_routes(bigint) is 'Save step: the routes the changed routesAdded, routeEdits and routeCabin items, frequencies and fare plans name. Added routes take their figures from routesAdded; a research route keeps its own, and one no longer added takes the research''s again (planner_data).';
comment on function private.planner_apply_fleet(bigint) is 'Save step: one aircraft row per changed registration from its tail and its delivery, with each list''s place in extra kept in step with the document''s order.';
comment on function private.planner_apply_flights(bigint) is 'Save step: changed frequencies as a rotation and two legs in UTC, exactly as the loader works them out (design §4), and changed plan cards with their legs in UTC.';
comment on function private.planner_apply_work(bigint, boolean) is 'Save step: changed to-dos and their steps, fare plans, interline, monthly checks, dismissed alerts, kept cabins, money spent and growth moves. Entries without an id are added and removed by what they say; when the stored order no longer matches the document''s, the rest of the list is written again in order (unless p_keep_order is false).';
comment on function private.planner_apply_money(bigint) is 'Save step: cash and next-7-day figures (design §8): a cash_entries row holds a figure only where it differs from the capture''s (rounded as the planner rounds), in AS$, and goes once both agree again.';
comment on function private.planner_apply_tidy(bigint) is 'Save step, after the others: aircraft in neither list (retired where the capture or money spent still point at them, else removed or taken out of the lists), routes nothing names any more and the research doesn''t have, and ref entries no longer listed, unless something still uses them.';
comment on function private.planner_apply_extra(bigint) is 'Save step, last: builds the document again and keeps in extra, as saved, any key of a written tail, delivery, frequency, plan card, to-do or fare plan that the columns don''t give back (the loader''s last step, for the items just written). Returns the document as the tables now give it.';
comment on function private.planner_apply(bigint, jsonb, text, timestamp with time zone, text, text, text) is 'Saves a planner document into a world''s tables, writing only the rows of the items that differ (design §8): a lock per world; the document and the tables as items; in mode save, items someone else changed after p_base are skipped (§11, choice 4); mode mirror (the side by side) and item (planner_item_put) skip nothing; the rest written as p_actor with p_detail (left as set when p_actor is null). Returns {applied, skipped, skipped_items, rows, doc}.';
comment on function private.planner_doc_with_item(jsonb, text, text, jsonb) is 'A planner document with one item set, or removed (p_value null), in today''s JSON shape. Sections: plans, routeEdits, routeCabin, interline, dismissed, cabinKeep by key; cash and fixed7 by date ({airline: millions}); monthly by airline ({task: date}); tails, deliveries, freqs, todos and farePlan by id; routesAdded by Airline|HUB|DEST; ref.hubs by Airline|CODE, ref.types by name, ref.configs and ref.services by code (set in place, or added at the end); ref.markets, ref.curfews, ref.utcOverrides, ref.gameLinks and ref.consts by key; ref.timeMode alone; capex and growthLog by place in the list (0 first; no key adds at the end).';
comment on function private.caller_is_staff() is 'True for planner staff (their sign-in) and for postgres itself (Claude, jobs, migrations), the way the getters decide. Used by the write functions that run as owner.';
comment on function private.loads_mirror_days(bigint, jsonb, timestamp with time zone) is 'Makes the tables give back the given loads days as planner_loads has them (design §8): each flight whose load the getter shows differently becomes a load_entries row stamped p_at (null clears it), and a day whose done or savedAt differs a load_days row. Days not given are left alone. Used by save_loads() and the side by side.';
comment on function private.adapter_seen(text) is 'Whether this version of an old row was already copied and compared in this transaction, and marks it so: the side-by-side triggers run at commit once per write, and the first does the work.';
comment on function private.adapter_mirror_state() is 'Trigger on planner_state, the side by side (design §9), run when the saving transaction commits: copies the row as it then stands into the tables (mirror mode, actor planner, detail mirror) and compares planner_state_get() with it (private.planner_state_check). One job_runs row each (adapter_mirror, adapter_check): ok, or failed with where in note and the paths in details. Catches every error, so the save always goes through. Runs as owner to write job_runs. Removed at the switch-over (pull request 9).';
comment on function private.adapter_mirror_loads() is 'Trigger on planner_loads, the side by side (design §9), run when the writing transaction commits (the capture writes a month once per day): copies the month''s days as they then stand into load_entries and load_days and compares planner_loads_get()''s month with them. One job_runs row each; catches every error. Runs as owner to write job_runs. Removed at the switch-over (pull request 9).';

select set_config('equinox.actor', '', true), set_config('equinox.actor_detail', '', true);

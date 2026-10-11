-- The switch-over: the planner reads and saves the tables (decision #13, build pull request 9).
-- Design: docs/design/2026-10-09-data-model.md (§8 "At the switch-over", §9 "Rollback", §10 row 9, §11 choices 3 and 4).
-- Spec: docs/specs/2026-10-10-switch-over.md.
--
-- Removes or revokes nothing. The side by side's two triggers and the browsers' write access to the old rows go in
-- 20261010230000_switch_over_removals.sql, which Gitesh runs first (manual §1).
--   1. the freeze: planner_state and planner_loads refuse every write, "frozen since <date>; write to the tables";
--   2. a loads day's done, one rule (design §8): public.loads_day_captured(), which the getter and the capture both use;
--   3. while the old rows are frozen, the capture's loads step leaves planner_loads alone and save_loads() writes only
--      the tables; unfrozen (after a rollback) both behave exactly as before;
--   4. planner_state_put(): a save's base covers its whole millisecond, so a tab that reloaded after someone else's
--      change can then change that item itself;
--   5. the cash allowances end: the side by side's comparison (private.planner_state_check) is strict;
--   6. rollback in one step: private.unfreeze_planner_state();
--   7. the switch: planner_loads copied into the tables one last time (the loader's loads step), so nothing
--      on screen moves, then both old rows frozen;
--   8. access and descriptions.
-- Apply it when no capture is running.

select set_config('equinox.actor', 'migration', true), set_config('equinox.actor_detail', '20261010231000_switch_over', true);

-- ============================================================ 1. the freeze (design §8, "At the switch-over")
-- Since when planner_state or planner_loads is frozen (its planner_frozen trigger's argument, e.g. "2026-10-11 03:12
-- UTC"), or null while it isn't
create or replace function private.planner_frozen_since(p_table regclass)
 returns text
 language sql
 stable
 set search_path to ''
as $function$
  select split_part(encode(t.tgargs, 'escape'), '\000', 1)
    from pg_catalog.pg_trigger t
   where t.tgrelid = p_table and t.tgname = 'planner_frozen' and t.tgenabled <> 'D'
$function$;

-- The freeze itself: refuses the write, whoever sends it (postgres included). A statement trigger, so an insert,
-- update, delete or truncate is refused before it touches a row.
create or replace function private.planner_frozen()
 returns trigger
 language plpgsql
 set search_path to ''
as $function$
begin
  raise exception 'frozen since %; write to the tables', tg_argv[0]
    using errcode = '42501',
          detail = format('%s is the old planner''s storage, kept unchanged as the fallback since the switch-over (#13, design §8).', tg_table_name),
          hint = 'The planner saves through planner_state_put() and save_loads(). A data-only change goes through planner_item_put() or plain SQL after the equinox.actor line (manual §1). private.unfreeze_planner_state() undoes the switch-over.';
end
$function$;

-- Freezes both old rows (the trigger planner_frozen on each), with the moment as its argument. A row already frozen
-- stays as it is, so freezing again keeps the first moment. Returns the moment.
create or replace function private.freeze_planner_state()
 returns text
 language plpgsql
 set search_path to ''
as $function$
declare v_since text := coalesce(private.planner_frozen_since('public.planner_state'::regclass),
                                 private.planner_frozen_since('public.planner_loads'::regclass),
                                 to_char(now() at time zone 'UTC', 'YYYY-MM-DD HH24:MI') || ' UTC');
  t text;
begin
  foreach t in array array['planner_state', 'planner_loads'] loop
    if private.planner_frozen_since(('public.' || t)::regclass) is not null then
      continue;
    elsif exists (select 1 from pg_catalog.pg_trigger x where x.tgrelid = ('public.' || t)::regclass and x.tgname = 'planner_frozen') then
      execute format('alter table public.%I enable trigger planner_frozen', t);   -- switched off by hand: on again
    else
      execute format('create trigger planner_frozen before insert or update or delete or truncate on public.%I '
                     'for each statement execute function private.planner_frozen(%L)', t, v_since);
      execute format('comment on trigger planner_frozen on public.%I is %L', t,
                     'The switch-over (#13, design §8): refuses every write to the old row, "frozen since ' || v_since
                     || '; write to the tables". private.unfreeze_planner_state() lifts it.');
    end if;
  end loop;
  return v_since;
end
$function$;

-- ============================================================ 2. a loads day's done: one rule (design §8)
-- True when every active airline of our groups in the world was captured for that date: its loads page of that date's
-- capture day is in (game_capture_raw, kept 14 days), or a flight of that date has loads captured in that capture day
-- or later (game_flights, kept a month). Part-way through an evening's capture, the airlines not captured yet have only
-- the evening before's loads for the date, so the day isn't done until the last one is in. The getter and the
-- capture's loads step both use it.
create or replace function public.loads_day_captured(p_world_id bigint, p_day date)
 returns boolean
 language plpgsql
 stable
 security invoker
 set search_path to ''
as $function$
declare v_from timestamptz;
begin
  if not (current_user = 'postgres' or public.is_planner_user()) then
    raise exception 'only planner staff can read the planner' using errcode = '42501';
  end if;
  -- the date's capture day starts at capture_day_starts_utc (design §2)
  v_from := (p_day + coalesce((select (s.value #>> '{}')::time from public.settings s
                               where s.world_id = p_world_id and s.airline_id is null and s.key = 'capture_day_starts_utc'),
                              time '10:00')) at time zone 'UTC';
  return exists (select 1 from public.airlines a join public.groups g on g.id = a.group_id and g.world_id = a.world_id
                  where a.world_id = p_world_id and a.active and g.kind = 'ours')
     and not exists (
           select 1 from public.airlines a join public.groups g on g.id = a.group_id and g.world_id = a.world_id
            where a.world_id = p_world_id and a.active and g.kind = 'ours'
              and not exists (select 1 from public.game_flights f
                               where f.airline_id = a.id and f.game_date = p_day and f.flight_no is not null
                                 and f.loads_captured_at >= v_from)
              and not exists (select 1 from public.game_capture_raw r
                               where r.airline_id = a.id and r.kind = 'loads'
                                 and r.captured_at >= v_from and r.captured_at < v_from + interval '1 day'));
end
$function$;

-- Today's planner_loads documents, one row per month like planner_loads, built from game_flights, load_entries and
-- load_days (design §8). As pull request 4 made it, with one change: a day's done follows public.loads_day_captured().
-- A day holds:
--   f: each flight's economy load, keyed "Airline|number". The capture's figure, or a typed one (load_entries; null
--      means cleared) when it was written after the capture's loads last covered that day for that airline, or the
--      capture has no figure. The latest write wins.
--   done: as typed (load_days), unless a capture came later: then true once every active airline of the world was
--      captured for that date (public.loads_day_captured);
--   source and captured: when the capture wrote the day (the latest loads capture of an airline flying that day, made
--      no more than 3 days after it);
--   savedAt: when the planner saved the day.
create or replace function public.planner_loads_get(p_world_id bigint default null)
 returns table (month text, "json" text, saved_at bigint)
 language plpgsql
 stable
 security invoker
 set search_path to ''
as $function$
#variable_conflict use_column
declare w bigint;
begin
  if not (current_user = 'postgres' or public.is_planner_user()) then
    raise exception 'only planner staff can read the planner' using errcode = '42501';
  end if;
  select x.id into w from public.worlds x where x.id = p_world_id or (p_world_id is null and x.is_default);
  if w is null then raise exception 'no such world: %', p_world_id; end if;
  return query
  with ours as (
    select a.id, a.planner_name, a.active from public.airlines a
      join public.groups g on g.id = a.group_id and g.world_id = a.world_id
     where a.world_id = w and g.kind = 'ours'),
  flown as (
    select f.airline_id, f.game_date, f.flight_no, f.eco_pct, f.loads_captured_at
      from public.game_flights f join ours on ours.id = f.airline_id
     where f.flight_no is not null and f.game_date is not null),
  -- each airline's loads captures: its kept pages, and the times its flights were last written
  captures as (
    select r.airline_id, r.captured_at from public.game_capture_raw r join ours on ours.id = r.airline_id where r.kind = 'loads'
    union
    select f.airline_id, f.loads_captured_at from flown f where f.loads_captured_at is not null),
  -- when the loads step last ran over a day for an airline flying it
  stamped as (
    select x.airline_id, x.day, max(c.captured_at) as at
      from (select distinct f.airline_id, f.game_date as day from flown f) x
      join captures c on c.airline_id = x.airline_id and (c.captured_at at time zone 'UTC')::date - 3 <= x.day
     group by x.airline_id, x.day),
  caught as (
    select f.airline_id, f.game_date as day, f.flight_no, max(f.eco_pct) as eco_pct
      from flown f where f.eco_pct is not null group by f.airline_id, f.game_date, f.flight_no),
  typed as (select * from public.load_entries e where e.world_id = w),
  loads as (
    select coalesce(c.airline_id, e.airline_id) as airline_id, coalesce(c.day, e.game_date) as day,
           coalesce(c.flight_no, e.flight_no) as flight_no,
           case when e.airline_id is not null and (c.eco_pct is null or s.at is null or e.entered_at is null or e.entered_at >= s.at)
                then trim_scale(e.eco_pct) else c.eco_pct end as v
      from caught c
      full join typed e on e.airline_id = c.airline_id and e.game_date = c.day and e.flight_no = c.flight_no
      left join stamped s on s.airline_id = coalesce(c.airline_id, e.airline_id) and s.day = coalesce(c.day, e.game_date)),
  days as (
    select f.game_date as day from flown f
    union select ld.game_date from public.load_days ld where ld.world_id = w
    union select e.game_date from typed e),
  day_stamp as (select s.day, max(s.at) as at from stamped s group by s.day),
  doc_days as (
    select d.day,
           jsonb_build_object(
             'f', coalesce((select jsonb_object_agg(o.planner_name || '|' || l.flight_no, l.v)
                              from loads l join ours o on o.id = l.airline_id
                             where l.day = d.day and l.v is not null), '{}'::jsonb),
             'done', case when ld.game_date is null then c.complete
                          when ds.at is not null and (ld.entered_at is null or ds.at > ld.entered_at) then ld.done or c.complete
                          else ld.done end)
           || case when ds.day is null then '{}'::jsonb
                   else jsonb_build_object('source', 'capture',
                                           'captured', (to_jsonb(ds.at at time zone 'UTC') #>> '{}') || '+00:00') end
           || case when ld.saved_at_ms is null then '{}'::jsonb else jsonb_build_object('savedAt', ld.saved_at_ms) end as j,
           greatest(ds.at, ld.entered_at, (select max(e.entered_at) from typed e where e.game_date = d.day),
                    to_timestamp(ld.saved_at_ms / 1000.0)) as at
      from days d
      left join public.load_days ld on ld.world_id = w and ld.game_date = d.day
      left join day_stamp ds on ds.day = d.day
      -- the one rule (design §8): every active airline of the world was captured for that date
      cross join lateral (select public.loads_day_captured(w, d.day) as complete) c)
  select to_char(dd.day, 'YYYY-MM'),
         jsonb_object_agg(dd.day::text, dd.j)::text,
         coalesce(floor(extract(epoch from max(dd.at)) * 1000)::bigint, 0)
    from doc_days dd
   group by to_char(dd.day, 'YYYY-MM')
   order by 1;
end
$function$;

-- The loader's loads step (pull request 4), with the getter's rule for a day's done (public.loads_day_captured), so a
-- day flag it leaves to the capture is one the getter gives back. For every day of planner_loads: each flight's figure
-- the capture doesn't give back becomes a load_entries row, and a captured flight the day doesn't show a cleared one; a
-- day's flags become a load_days row when the planner saved the day, the capture didn't write it, or its done differs
-- from the getter's. Stamped no earlier than the month's last write and the latest loads capture, so they win over the
-- capture as they did. Used after a rollback, and by the tests.
create or replace function private.load_planner_loads(p_world_id bigint)
 returns jsonb
 language plpgsql
 set search_path to ''
as $function$
declare w bigint := p_world_id; n_entries int; n_days int;
begin
  if to_regclass('pg_temp.t_load_loads') is null then
    create temporary table t_load_loads (airline_id bigint, game_date date, flight_no int, eco_pct numeric,
                                                     entered_at timestamptz) on commit drop;
  end if;
  if to_regclass('pg_temp.t_load_days') is null then
    create temporary table t_load_days (game_date date, done boolean, saved_at_ms bigint, entered_at timestamptz) on commit drop;
  end if;
  truncate pg_temp.t_load_loads, pg_temp.t_load_days;
  with ours as (
    select a.id, a.planner_name, a.active from public.airlines a
      join public.groups g on g.id = a.group_id and g.world_id = a.world_id
     where a.world_id = w and g.kind = 'ours'),
  latest as (select max(f.loads_captured_at) as at from public.game_flights f join ours on ours.id = f.airline_id),
  months as (select pl.month, private.json_object_or_empty(pl.json) as j,
                    greatest(to_timestamp(pl.saved_at / 1000.0), (select at from latest)) as stamp
               from public.planner_loads pl),
  days as (select m.stamp, private.json_date(to_jsonb(e.key)) as day, e.value as v
             from months m cross join lateral jsonb_each(m.j) e
            where jsonb_typeof(e.value) = 'object' and private.json_date(to_jsonb(e.key)) is not null),
  stored as (
    select d.day, d.stamp, o.id as airline_id, private.json_int(to_jsonb(split_part(f.key, '|', 2))) as flight_no,
           private.json_num(f.value) as v
      from days d
      cross join lateral jsonb_each(case when jsonb_typeof(d.v -> 'f') = 'object' then d.v -> 'f' else '{}'::jsonb end) f
      join ours o on o.planner_name = split_part(f.key, '|', 1)),
  caught as (
    select f.airline_id, f.game_date as day, f.flight_no, max(f.eco_pct) as v
      from public.game_flights f join ours on ours.id = f.airline_id
     where f.flight_no is not null and f.eco_pct is not null
     group by f.airline_id, f.game_date, f.flight_no)
  insert into pg_temp.t_load_loads
  select st.airline_id, st.day, st.flight_no, st.v, st.stamp
    from stored st
    left join caught c on c.airline_id = st.airline_id and c.day = st.day and c.flight_no = st.flight_no
   where st.flight_no between 0 and 2000000000 and abs(st.v) < 10000 and st.v is distinct from c.v
  union all
  select c.airline_id, c.day, c.flight_no, null, d.stamp
    from caught c join days d on d.day = c.day
   where not exists (select 1 from stored st where st.airline_id = c.airline_id and st.day = c.day and st.flight_no = c.flight_no);

  with ours as (
    select a.id, a.active from public.airlines a
      join public.groups g on g.id = a.group_id and g.world_id = a.world_id
     where a.world_id = w and g.kind = 'ours'),
  latest as (select max(f.loads_captured_at) as at from public.game_flights f join ours on ours.id = f.airline_id),
  days as (select greatest(to_timestamp(pl.saved_at / 1000.0), (select at from latest)) as stamp,
                  private.json_date(to_jsonb(e.key)) as day, e.value as v
             from public.planner_loads pl cross join lateral jsonb_each(private.json_object_or_empty(pl.json)) e
            where jsonb_typeof(e.value) = 'object' and private.json_date(to_jsonb(e.key)) is not null),
  judged as (
    select d.*,
           exists (select 1 from public.game_flights f join ours on ours.id = f.airline_id
                    where f.flight_no is not null and f.game_date = d.day) as captured,
           -- the getter's done for a captured day: the one rule (public.loads_day_captured)
           public.loads_day_captured(w, d.day) as complete
      from days d)
  insert into pg_temp.t_load_days
  select j.day, coalesce(j.v -> 'done' = 'true'::jsonb, false), private.json_int(j.v -> 'savedAt'), j.stamp
    from judged j
   where j.v ? 'savedAt' or not j.captured or coalesce(j.v -> 'done' = 'true'::jsonb, false) <> j.complete;

  insert into public.load_entries as x (world_id, airline_id, game_date, flight_no, eco_pct, entered_at)
  select w, l.airline_id, l.game_date, l.flight_no, l.eco_pct, l.entered_at from pg_temp.t_load_loads l
  on conflict (airline_id, game_date, flight_no) do update set eco_pct = excluded.eco_pct, entered_at = excluded.entered_at
  where (x.eco_pct, x.entered_at) is distinct from (excluded.eco_pct, excluded.entered_at);
  get diagnostics n_entries = row_count;
  delete from public.load_entries x
   where x.world_id = w
     and not exists (select 1 from pg_temp.t_load_loads l
                      where l.airline_id = x.airline_id and l.game_date = x.game_date and l.flight_no = x.flight_no);
  insert into public.load_days as x (world_id, game_date, done, saved_at_ms, entered_at)
  select w, d.game_date, d.done, d.saved_at_ms, d.entered_at from pg_temp.t_load_days d
  on conflict (world_id, game_date) do update set done = excluded.done, saved_at_ms = excluded.saved_at_ms,
    entered_at = excluded.entered_at
  where (x.done, x.saved_at_ms, x.entered_at) is distinct from (excluded.done, excluded.saved_at_ms, excluded.entered_at);
  get diagnostics n_days = row_count;
  delete from public.load_days x
   where x.world_id = w and not exists (select 1 from pg_temp.t_load_days d where d.game_date = x.game_date);
  return jsonb_build_object('load_entries', n_entries, 'load_days', n_days);
end
$function$;

-- ============================================================ 3. loads: the capture and save_loads()
-- The capture's loads step. While planner_loads is frozen it does nothing: the loads are in game_flights already, where
-- planner_loads_get() reads them. Unfrozen (before the switch-over, or after a rollback) it copies the last 3 days of an
-- airline's captured loads into planner_loads as before, with the month's saved_at moved on; a day is done once every
-- active airline was captured for that date (public.loads_day_captured, the getter's rule), and a day already done
-- stays done.
create or replace function private.apply_loads_from_capture(p_airline_id bigint)
 returns jsonb
 language plpgsql
 set search_path to ''
as $function$
declare d record; mon text; cur jsonb; day jsonb; f jsonb; n int := 0; v_name text; v_world bigint;
  ms bigint := (extract(epoch from clock_timestamp()) * 1000)::bigint;
begin
  if private.planner_frozen_since('public.planner_loads'::regclass) is not null then
    return jsonb_build_object('days', 0);
  end if;
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
                                             or public.loads_day_captured(v_world, d.game_date),
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

-- save_loads(): the same name, arguments and answer as before. Each day given is merged onto the day as it stands
-- (a whole day's flights with f, or single flights with set and del, plus done and savedAt), so days captured since the
-- page loaded aren't lost.
--   Frozen (since the switch-over): the day as planner_loads_get() gives it is the one merged onto, and the result is
--     written to load_entries and load_days only (private.loads_mirror_days), as actor planner, detail save_loads. A
--     failure stops the save. The answer is the month as planner_loads_get() now gives it.
--   Unfrozen (before the switch-over, or after a rollback): exactly as pull request 5 left it: planner_loads, and the
--     tables too.
create or replace function public.save_loads(p_month text, p_days jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare cur jsonb; d text; p jsonb; day jsonb; f jsonb; v_days jsonb := '{}'::jsonb; w bigint; v_saved bigint;
  ms bigint := (extract(epoch from clock_timestamp()) * 1000)::bigint;
  v_actor text := current_setting('equinox.actor', true); v_detail text := current_setting('equinox.actor_detail', true);
  v_frozen boolean := private.planner_frozen_since('public.planner_loads'::regclass) is not null;
begin
  if not public.is_planner_user() then raise exception 'only planner staff can save loads' using errcode = '42501'; end if;
  if p_month is null or p_month !~ '^\d{4}-\d{2}$' then raise exception 'month must be YYYY-MM, got %', p_month; end if;
  if jsonb_typeof(p_days) is distinct from 'object' then raise exception 'days must be an object keyed by date'; end if;
  select x.id into w from public.worlds x where x.is_default;
  if v_frozen then
    -- two saves of one month queue instead of racing
    perform pg_advisory_xact_lock(hashtextextended('equinox loads ' || p_month, w));
    select g.json::jsonb into cur from public.planner_loads_get(w) g where g.month = p_month;
  else
    insert into public.planner_loads (month, json, saved_at) values (p_month, '{}', 0) on conflict (month) do nothing;
    select pl.json::jsonb into cur from public.planner_loads pl where pl.month = p_month for update;
  end if;
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

  if v_frozen then
    perform set_config('equinox.actor', 'planner', true), set_config('equinox.actor_detail', 'save_loads', true);
    perform private.loads_mirror_days(w, v_days, now());
    perform set_config('equinox.actor', coalesce(v_actor, ''), true), set_config('equinox.actor_detail', coalesce(v_detail, ''), true);
    select g.json::jsonb, g.saved_at into cur, v_saved from public.planner_loads_get(w) g where g.month = p_month;
    return jsonb_build_object('month', p_month, 'json', coalesce(cur, '{}'::jsonb), 'saved_at', coalesce(v_saved, ms));
  end if;

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

-- ============================================================ 4. planner_state_put(): a base covers its millisecond
-- As pull request 5 made it, with one fix found at the switch-over. A tab's base is planner_state_version(): the time of
-- the latest change in whole milliseconds, rounded down. Read as that exact moment, a change made inside that same
-- millisecond (by Claude, say) counted as newer than the base, so a tab that had just reloaded to pick it up was told
-- to reload again on every save of that item. A base now covers its whole millisecond: only changes from the next
-- millisecond on are newer than it.
create or replace function public.planner_state_put(p_json text, p_saved_at bigint, p_base bigint, p_client text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare w bigint; v_doc jsonb; v_res jsonb; v_since timestamptz;
begin
  if not private.caller_is_staff() then raise exception 'only planner staff can save the planner' using errcode = '42501'; end if;
  begin
    v_doc := p_json::jsonb;
  exception when others then
    raise exception 'the planner document isn''t JSON' using errcode = '22023';
  end;
  if jsonb_typeof(v_doc) is distinct from 'object' then raise exception 'the planner document isn''t a JSON object' using errcode = '22023'; end if;
  select x.id into w from public.worlds x where x.is_default;
  -- the last microsecond of the base's millisecond (exact interval arithmetic, no floating point)
  v_since := timestamptz 'epoch' + (coalesce(p_base, p_saved_at) + 1) * interval '1 millisecond' - interval '1 microsecond';
  v_res := private.planner_apply(w, v_doc, 'save', v_since, nullif(p_client, ''), 'planner', nullif(p_client, ''));
  return jsonb_build_object('saved_at', public.planner_state_version(w), 'applied', v_res -> 'applied',
                            'skipped', v_res -> 'skipped', 'reload', (v_res ->> 'skipped')::int > 0,
                            'skipped_items', v_res -> 'skipped_items');
end
$function$;

-- ============================================================ 5. the cash allowances end
-- The side by side's comparison of a planner_state document with the one built from the tables: since the switch-over
-- strict. Only design §9's differences are allowed (private.planner_json_diff's kinds); the two cash and next-7-day
-- allowances that served the side by side (a capture after the planner last saved, and one a stale tab's document
-- didn't have yet) end, because the getter is now the source. A cash or fixed7 difference still says why (dates and
-- airlines, never figures). Used only if a rollback puts the side by side back.
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
                when cc.fixed_next7 > 0 then floor(cc.fixed_next7 / 10000 + 0.5) / 100 end as figure
      from entries e
      left join public.airlines al on al.planner_name = e.airline and al.world_id = p_world_id
      left join public.capture_cash cc on cc.airline_id = al.id and cc.day = private.json_date(to_jsonb(e.day)))
  select d.path, d.kind,
         case when d.kind = 'differs' then
           (select string_agg(format('%s %s %s (%s; %s)', m.sec, m.day, m.airline,
                     case when m.had is null then 'only in the tables' when m.got is null then 'only in planner_state' else 'the figure differs' end,
                     case when m.cash_at is null then 'no capture that date'
                          when m.figure is distinct from (case when jsonb_typeof(m.got) = 'number' then (m.got #>> '{}')::numeric end) then 'not the capture''s figure'
                          when m.cash_at > to_timestamp(p_saved_at / 1000.0) then 'captured after the planner last saved'
                          else 'captured before the planner last saved' end), ', ' order by m.sec, m.day, m.airline)
              from money m where m.path = d.path) end
    from d
$function$;

-- ============================================================ 6. rollback in one step (design §9)
-- Undoes the switch-over in the database: writes planner_state and planner_loads from the getters, so nothing saved
-- since the switch is lost; lifts the freeze; gives signed-in staff back the planner_state writes the old planner makes
-- (insert and update; the policies were never removed); and puts the side by side back (the two adapter_mirror
-- triggers of pull request 5), so the old planner's saves keep the tables, and so the website, current. The capture's
-- loads step and save_loads() write planner_loads again as soon as it is unfrozen. It doesn't revert the planner's code:
-- revert the switch-over's pull request too (the pull request says how). Postgres only (Claude in a chat, after the
-- equinox.actor line; or Gitesh in Supabase's SQL editor). Returns what it did.
create or replace function private.unfreeze_planner_state()
 returns jsonb
 language plpgsql
 set search_path to ''
as $function$
declare w bigint := (select x.id from public.worlds x where x.is_default);
  v_since text := coalesce(private.planner_frozen_since('public.planner_state'::regclass),
                           private.planner_frozen_since('public.planner_loads'::regclass));
  g jsonb; n_months int;
begin
  -- no planner save or item put runs meanwhile
  perform pg_advisory_xact_lock(hashtextextended('equinox planner world', w));
  drop trigger if exists planner_frozen on public.planner_state;
  drop trigger if exists planner_frozen on public.planner_loads;
  g := public.planner_state_get(w);
  insert into public.planner_state (id, json, saved_at) values ('main', g ->> 'json', (g ->> 'saved_at')::bigint)
  on conflict (id) do update set json = excluded.json, saved_at = excluded.saved_at;
  insert into public.planner_loads (month, json, saved_at)
  select l.month, l.json, l.saved_at from public.planner_loads_get(w) l
  on conflict (month) do update set json = excluded.json, saved_at = excluded.saved_at;
  get diagnostics n_months = row_count;
  grant insert, update on table public.planner_state to authenticated;
  -- the side by side again (after the writes above, so they aren't copied back)
  if not exists (select 1 from pg_catalog.pg_trigger x where x.tgrelid = 'public.planner_state'::regclass and x.tgname = 'adapter_mirror') then
    create constraint trigger adapter_mirror after insert or update on public.planner_state
      deferrable initially deferred for each row execute function private.adapter_mirror_state();
  end if;
  if not exists (select 1 from pg_catalog.pg_trigger x where x.tgrelid = 'public.planner_loads'::regclass and x.tgname = 'adapter_mirror') then
    create constraint trigger adapter_mirror after insert or update on public.planner_loads
      deferrable initially deferred for each row execute function private.adapter_mirror_loads();
  end if;
  return jsonb_build_object('was_frozen_since', v_since, 'planner_state_saved_at', (g ->> 'saved_at')::bigint,
                            'planner_loads_months', n_months, 'side_by_side', 'on',
                            'next', 'revert the switch-over''s pull request, then reload every open planner tab');
end
$function$;

-- ============================================================ 7. the switch
-- The last copy of planner_loads: the loader's loads step (above, with the loads day's done rule) over planner_loads as
-- it is now, logged as migration, so the getter gives back every day as the planner showed it the moment it switches.
-- One job_runs row says so. Then both old rows are frozen. (planner_state isn't copied again: the side by side kept the
-- tables equal to it, and since this pull request's planner was published it saves into the tables, which a copy of
-- the older row would undo.)
do $switch$
declare w bigint := (select x.id from public.worlds x where x.is_default); t0 timestamptz := clock_timestamp(); v_res jsonb;
begin
  v_res := private.load_planner_loads(w);
  perform private.job_run_add('adapter_mirror', w, t0, 'ok',
    format('planner_loads at the switch-over: %s load(s) and %s day flag(s) written; planner_state and planner_loads frozen',
           v_res ->> 'load_entries', v_res ->> 'load_days'),
    jsonb_build_object('table', 'planner_loads', 'rows', v_res, 'migration', '20261010231000_switch_over'));
  perform private.freeze_planner_state();
end
$switch$;

-- ============================================================ 8. access (design §5)
revoke all on function public.loads_day_captured(bigint, date) from public, anon, authenticated;
grant execute on function public.loads_day_captured(bigint, date) to authenticated;
revoke all on function private.planner_frozen_since(regclass), private.planner_frozen(), private.freeze_planner_state(),
  private.unfreeze_planner_state()
  from public, anon, authenticated;

-- ============================================================ descriptions (decision #10)
comment on table public.planner_state is 'The old planner''s whole state in one JSON row (id main). Frozen since the switch-over (#13, pull request 9): every write is refused ("frozen since <date>; write to the tables"), and it is kept unchanged as the fallback until #18. The planner reads planner_state_get() and saves through planner_state_put(); the tables are the truth. private.unfreeze_planner_state() undoes the switch-over.';
comment on table public.planner_loads is 'The old planner''s daily loads, one JSON document per month. Frozen since the switch-over (#13, pull request 9): every write is refused, the capture''s loads step leaves it alone and save_loads() writes the tables, and it is kept unchanged as the fallback until #18. The planner reads planner_loads_get(). private.unfreeze_planner_state() undoes the switch-over.';
comment on column public.planner_state.saved_at is 'When it was last saved, in milliseconds since 1970 (UTC). Since the switch-over the planner uses planner_state_version() instead';
comment on function private.planner_frozen_since(regclass) is 'Since when planner_state or planner_loads is frozen (its planner_frozen trigger''s argument, e.g. "2026-10-11 03:12 UTC"), or null while it isn''t. The capture''s loads step and save_loads() ask it.';
comment on function private.planner_frozen() is 'Trigger on planner_state and planner_loads since the switch-over (#13, design §8): refuses every insert, update, delete or truncate, whoever sends it, with "frozen since <date>; write to the tables" and a hint naming the adapter and private.unfreeze_planner_state().';
comment on function private.freeze_planner_state() is 'Freezes planner_state and planner_loads (the planner_frozen trigger on each, with the moment as its argument); freezing again keeps the first moment. Run by the switch-over''s migration; after a rollback, running it again (with the removal file of 20261010230000) switches over again. Returns the moment.';
comment on function private.unfreeze_planner_state() is 'The switch-over''s rollback in one step (design §9): writes planner_state and planner_loads from the getters, so nothing saved since the switch is lost; lifts the freeze; gives signed-in staff back planner_state''s insert and update; and puts the side by side back (the adapter_mirror triggers), so the old planner''s saves keep the tables and the website current. It doesn''t revert the planner''s code: revert the switch-over''s pull request too. Postgres only. Returns what it did.';
comment on function public.loads_day_captured(bigint, date) is 'A loads day''s done, one rule (design §8): true when every active airline of our groups in the world was captured for that date (its loads page of that capture day is in, or a flight of that date has loads captured in that capture day or later). planner_loads_get() and the capture''s loads step both use it, so part-way through an evening''s capture a day isn''t done until the last airline is in. Staff and postgres only.';
comment on function public.planner_loads_get(bigint) is 'The planner''s loads documents, built from game_flights, load_entries and load_days (design §8): one row per month, as planner_loads had them. Per flight, the latest write wins, captured or typed; a day is done when typed, or once every active airline was captured for that date (loads_day_captured). The planner reads it since the switch-over (#13, pull request 9). Staff only.';
comment on function public.planner_state_get(bigint) is 'The planner''s document built from the tables (design §8): {json: the document as text, saved_at: planner_state_version()}. Every list in the old planner''s order; cash and next-7-day costs from the capture unless typed; anything the tables have no column for from the row''s extra. The planner reads it since the switch-over (#13, pull request 9). Staff only.';
comment on function public.planner_state_version(bigint) is 'The time of the latest logged change to a world''s planner tables (or to airports and countries), in milliseconds rounded down, never earlier than the old planner_state row''s last save: the planner''s saved_at and the base it saves from (design §8). Staff only. Default: the default world.';
comment on function public.planner_state_put(text, bigint, bigint, text) is 'Saves the planner''s document into the tables (design §8), writing only the rows that changed; the planner saves through it since the switch-over (#13, pull request 9). Takes a lock per world; skips any item someone else (another actor, or another tab than p_client) changed after p_base, or after p_saved_at when there is no base (§11, choice 4). A base covers its whole millisecond (it is a planner_state_version(), rounded down). Writes the rest as actor planner with the tab in actor_detail. Answers {saved_at (server time, planner_state_version()), applied, skipped, reload (true when anything was skipped), skipped_items}. Staff and postgres only; runs as owner and checks the caller itself.';
comment on function public.save_loads(text, jsonb) is 'Saves the planner''s loads typed by hand: merges only the days given (a whole day''s flights with f, or single flights with set and del, plus done and savedAt) onto the days as they stand, so days captured since the page loaded aren''t lost, and returns the merged month. Since the switch-over (#13, pull request 9) it writes load_entries and load_days only (actor planner, detail save_loads) and returns the month as planner_loads_get() gives it; while planner_loads is unfrozen (after a rollback) it writes planner_loads and the tables, as before. Planner staff only; runs as owner.';
comment on function private.apply_loads_from_capture(bigint) is 'The capture''s loads step. Since the switch-over (#13, pull request 9), while planner_loads is frozen, it does nothing: the loads are in game_flights, where planner_loads_get() reads them. Unfrozen (after a rollback) it copies the last 3 days of an airline''s captured loads into planner_loads as before, a day done once every active airline was captured for that date (loads_day_captured, the getter''s rule) and staying done.';
comment on function private.load_planner_loads(bigint) is 'Loader step: every load in planner_loads the capture doesn''t give back becomes a load_entries row (null where a captured flight was cleared), and a day''s flags a load_days row where the planner saved the day, the capture didn''t write it, or its done differs from the getter''s (loads_day_captured, since the switch-over). Used after a rollback, and by the tests.';
comment on function private.planner_state_check(bigint, jsonb, bigint, jsonb) is 'The side by side''s comparison of a planner_state document with the one built from the tables. Strict since the switch-over (#13, pull request 9): only design §9''s differences are allowed, and the cash allowances that served the side by side ended. A cash or next-7-day difference says why (dates and airlines only). One row per difference: path, kind (''differs'' when not allowed), why. Used only if a rollback puts the side by side back.';
comment on function private.adapter_mirror_state() is 'The side by side (design §9) on planner_state: copies each save of the old row into the tables (mirror mode, actor planner, detail mirror) when the transaction commits, and compares planner_state_get() with it (private.planner_state_check); one job_runs row each, never stopping the save. Not attached since the switch-over (#13, pull request 9): private.unfreeze_planner_state() attaches it again.';
comment on function private.adapter_mirror_loads() is 'The side by side (design §9) on planner_loads: copies each write of a month into load_entries and load_days when the transaction commits, and compares planner_loads_get()''s month with it; one job_runs row each. Not attached since the switch-over (#13, pull request 9): private.unfreeze_planner_state() attaches it again.';
comment on function public.adapter_clean_days(bigint, timestamp with time zone) is 'How many clean days in a row the side by side had (design §11, choice 1), counted back from the capture day p_as_of falls in (default now; that day counts once it has a run, and a day still under way with none doesn''t break the run). A day with no comparison, or with any failed mirror or comparison, ends the run. The side by side ended at the switch-over (#13, pull request 9), so from then on it counts 0 unless a rollback puts it back. Staff and postgres only.';

select set_config('equinox.actor', '', true), set_config('equinox.actor_detail', '', true);

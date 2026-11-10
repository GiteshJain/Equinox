-- The unattended capture, part 1: the key, the settings, the dispatch (10 Nov 2026; to-do 203; spec
-- docs/specs/2026-11-10-unattended-capture.md §1, pull request 1 of 2; briefs docs/briefs/2026-11-10-unattended-capture.md,
-- option C, and docs/briefs/2026-11-10-unattended-capture-scope.md, option B).
--
-- Why: the game keeps loads and the bank statement for 24 hours, so one capture a day has no slack. Twice a day
-- (09:30 and 21:30 UTC) the database asks GitHub to start a job in equinox-backups that runs the same capture script with
-- its own key. This migration is the database's part; the job comes in the second pull request. Nothing posts until
-- Gitesh puts the GitHub token, and the project's address, in the vault (spec §7).
--
-- Adds a column, a setting in each of four rows per world, five internal functions, two scheduled jobs and pg_net; widens
-- one rule; replaces eight functions with the same arguments. Deletes and drops nothing else:
--   1. capture_keys.unattended (boolean, not null, default false; described). Every key there now stays false.
--   2. job_runs.job also takes capture_unattended (the GitHub job's run, written by it) and capture_dispatch (the
--      database's start). Its rule is replaced by the same rule with the two names added, in one statement, so no
--      moment is without it; nothing in the table changes.
--   3. Four settings, world rows in every world, described: unattended_salaries false, unattended_scan true,
--      unattended_market true (what an unattended key may do) and capture_unattended_warn_h 14 (when Today warns).
--   4. private.capture_key_issue(world, label, unattended): a new random key (32 bytes, hex), only its hash stored the way
--      private.capture_key_world() checks it (extensions.crypt with a bf salt); answers the key once. postgres only, so
--      Gitesh runs it in Supabase's SQL editor and the key never passes through a chat.
--      private.capture_key_unattended(key): whether a key is an unattended one (false for an unknown key).
--      private.capture_unattended_allows(world, what): the world's unattended_<what> setting (false without it).
--   5. With an unattended key: capture_airlines() answers salary_above_average_pct null while unattended_salaries is
--      false, the scan not due while unattended_scan is false, the market pages not due (and none listed) while
--      unattended_market is false, and unattended true; otherwise as for a normal key. A normal key answers exactly as
--      before. capture_fare_actions(), capture_fare_actions_by_airline(), capture_eval_runs() and capture_eval_result()
--      refuse an unattended key as they refuse a wrong one (fares are never changed on a schedule, manual §5);
--      capture_scan() and capture_market() refuse it while their setting is false. Their grants and settings are kept.
--   6. The dispatch: pg_net switched on. private.capture_dispatch() posts {"ref": "main"} to GitHub's
--      /repos/GiteshJain/equinox-backups/actions/workflows/capture.yml/dispatches with the vault's github_dispatch_token,
--      and writes one job_runs row (capture_dispatch): ok with pg_net's request id when the post was queued; ok
--      "skipped: a capture is running" when a capture page arrived in the last 20 minutes (or a world scan is open); failed
--      "no GitHub token in the vault", or failed "not the live project" unless the vault's project_url is this project's
--      address, posting nothing either way. private.capture_dispatch_answer() notes GitHub's answer on the dispatch's row
--      (204 ok; anything else makes the row failed, with the status and the first 200 characters).
--      The rehearsal's copy never posts: a backup carries no vault (it dumps only public and storage data), so the copy has
--      neither the token nor the project's address.
--   7. The schedule: private.schedule_jobs() also schedules equinox-capture-dispatch at 09:30 and 21:30 UTC and
--      equinox-capture-dispatch-answer at 09:40 and 21:40 UTC (pg_net keeps an answer 6 hours, so the next dispatch, 12
--      hours on, would find none), and is run here.
--   8. system_status() also answers unattended: the setting, the unattended capture's last run and last good run, and
--      the dispatch's last run, for the Systems board.

select set_config('equinox.actor', 'claude', true), set_config('equinox.actor_detail', 'building unattended capture', true);

-- ============================================================ 1. the key's mark
alter table public.capture_keys add column unattended boolean not null default false;
comment on column public.capture_keys.unattended is 'True for the unattended capture''s key (the GitHub job in equinox-backups, since 10 Nov; spec docs/specs/2026-11-10-unattended-capture.md): with it capture_airlines() follows the world''s unattended_salaries, unattended_scan and unattended_market settings, and the fares and aircraft evaluation calls refuse it. Issued with private.capture_key_issue(). False for every other key';

do $describe$
declare d text := obj_description('public.capture_keys'::regclass, 'pg_class');
begin
  if position('unattended' in coalesce(d, '')) = 0 then
    execute format('comment on table public.capture_keys is %L', coalesce(d, '')
      || ' Since 10 Nov a key may be marked unattended (the GitHub job''s; spec docs/specs/2026-11-10-unattended-capture.md), and private.capture_key_issue() issues a key, storing only its hash.');
  end if;
end
$describe$;

-- ============================================================ 2. job_runs takes the two new jobs
alter table public.job_runs
  drop constraint job_runs_job_check,
  add constraint job_runs_job_check check (job in ('backup', 'snapshot', 'snapshot_fallback', 'cleanup', 'archive', 'adapter_mirror',
                                                   'adapter_check', 'capture_unattended', 'capture_dispatch'));
comment on column public.job_runs.job is 'backup, snapshot, snapshot_fallback, cleanup or archive; since 10 Nov capture_dispatch (the database asking GitHub to start the unattended capture, 09:30 and 21:30 UTC) and capture_unattended (the unattended capture''s run, written by the GitHub job in equinox-backups); adapter_mirror and adapter_check are the old adapter''s runs, until the clean-up (build pull request 14)';

do $describe$
declare d text := obj_description('public.job_runs'::regclass, 'pg_class');
begin
  if position('capture_dispatch' in coalesce(d, '')) = 0 then
    execute format('comment on table public.job_runs is %L', coalesce(d, '')
      || ' Since 10 Nov also the unattended capture (spec docs/specs/2026-11-10-unattended-capture.md): capture_dispatch, the database asking GitHub to start it (private.capture_dispatch(), its answer noted on the same row), and capture_unattended, the run itself, written by the GitHub job.');
  end if;
end
$describe$;

-- ============================================================ 3. the settings
insert into public.settings (world_id, airline_id, key, value, unit, description, since, reason)
select w.id, null, x.key, x.value, x.unit, x.description, date '2026-11-10', x.reason
  from public.worlds w
 cross join (values
   ('unattended_salaries', 'false'::jsonb, null::text,
    'Whether the unattended capture (the GitHub job, twice a day; spec docs/specs/2026-11-10-unattended-capture.md) sets salaries (manual §7): '
    'false, so capture_airlines() answers salary_above_average_pct null for the unattended key and the capture leaves salaries alone; '
    'Gitesh''s own press sets them. Moving salaries to the job is changing this to true.',
    'Gitesh, 10 Nov: option B of docs/briefs/2026-11-10-unattended-capture-scope.md (salaries stay with his own press for now)'),
   ('unattended_scan', 'true'::jsonb, null::text,
    'Whether the unattended capture (the GitHub job, twice a day; spec docs/specs/2026-11-10-unattended-capture.md) does the world scan '
    'when one is due (scan_every_days), as Gitesh''s press does: true. False makes capture_airlines() answer the scan not due for the '
    'unattended key, and capture_scan() refuse that key.',
    'Gitesh, 10 Nov: option B of docs/briefs/2026-11-10-unattended-capture-scope.md (twice a day, with the world scan and the market pages)'),
   ('unattended_market', 'true'::jsonb, null::text,
    'Whether the unattended capture (the GitHub job, twice a day; spec docs/specs/2026-11-10-unattended-capture.md) reads the market pages '
    'when they''re due (market_every_days), as Gitesh''s press does: true. False makes capture_airlines() answer them not due for the '
    'unattended key, and capture_market() refuse that key.',
    'Gitesh, 10 Nov: option B of docs/briefs/2026-11-10-unattended-capture-scope.md (twice a day, with the world scan and the market pages)'),
   ('capture_unattended_warn_h', '14'::jsonb, 'hours',
    'Today''s needs attention warns "Unattended capture: last good run N hours ago" when the latest ok run of the unattended capture '
    '(job_runs, capture_unattended) is more than this many hours old; the Systems board''s line is green under it, amber to 26 hours and '
    'red beyond. Nothing is shown before the first good run. Runs are 12 hours apart (09:30 and 21:30 UTC).',
    'Spec docs/specs/2026-11-10-unattended-capture.md §3: one run late or failed is 14 hours, one missed run and a bit')
 ) as x(key, value, unit, description, reason)
on conflict on constraint settings_world_airline_key_key do nothing;

-- ============================================================ 4. the key's functions
create or replace function private.capture_key_unattended(p_key text)
returns boolean
language sql
stable
set search_path to ''
as $function$
  select coalesce((select k.unattended from public.capture_keys k
                    where p_key is not null and extensions.crypt(p_key, k.key_hash) = k.key_hash
                    order by k.id
                    limit 1), false)
$function$;

create or replace function private.capture_unattended_allows(p_world_id bigint, p_what text)
returns boolean
language sql
stable
set search_path to ''
as $function$
  select coalesce((select s.value = 'true'::jsonb from public.settings s
                    where s.world_id = p_world_id and s.airline_id is null and s.key = 'unattended_' || p_what), false)
$function$;

create or replace function private.capture_key_issue(p_world bigint, p_label text, p_unattended boolean)
returns text
language plpgsql
set search_path to ''
as $function$
declare v_key text;
begin
  if p_world is null or not exists (select 1 from public.worlds w where w.id = p_world) then
    raise exception 'no world %: name the world the key captures (public.worlds.id)', coalesce(p_world::text, 'null') using errcode = '22023';
  end if;
  if coalesce(btrim(p_label), '') = '' then
    raise exception 'name the key: a label says where it lives (e.g. ''unattended (GitHub)'')' using errcode = '22023';
  end if;
  v_key := encode(extensions.gen_random_bytes(32), 'hex');
  -- only the hash is kept, as private.capture_key_world() checks it
  insert into public.capture_keys (label, key_hash, world_id, unattended)
  values (btrim(p_label), extensions.crypt(v_key, extensions.gen_salt('bf')), p_world, coalesce(p_unattended, false));
  return v_key;
end
$function$;

-- ============================================================ 5. what an unattended key may do
create or replace function public.capture_airlines(p_key text)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare v_world bigint; v_unattended boolean; v_doc jsonb;
begin
  v_world := private.capture_key_world(p_key);
  if v_world is null then return jsonb_build_object('ok', false, 'error', 'bad key'); end if;
  -- the unattended capture's key (since 10 Nov, spec docs/specs/2026-11-10-unattended-capture.md §1)
  v_unattended := private.capture_key_unattended(p_key);
  v_doc := jsonb_build_object(
    'ok', true,
    'world', (select w.name from public.worlds w where w.id = v_world),
    'airlines', (select coalesce(jsonb_agg(jsonb_build_object('game_id', a.game_id, 'name', a.planner_name,
                                                               'game_name', a.game_name, 'code', a.iata_code)
                                           order by a.position nulls last, a.id), '[]'::jsonb)
                   from public.airlines a join public.groups g on g.id = a.group_id and g.world_id = a.world_id
                  where a.world_id = v_world and a.active and g.kind = 'ours'),
    -- salaries (since 5 Nov, manual §7): how far above the country average a salary below it is set; null: left alone
    -- (and null for the unattended key while unattended_salaries is false)
    'salary_above_average_pct', case when v_unattended and not private.capture_unattended_allows(v_world, 'salaries') then null
                                     else (select s.value from public.settings s
                                            where s.world_id = v_world and s.airline_id is null and s.key = 'salary_above_average_pct') end)
    -- the world scan (spec docs/specs/2026-10-21-scan-in-capture.md): whether one is due, the open one and the airports
    || private.capture_scan_plan(v_world, now())
    -- the market pages (spec docs/specs/2026-10-30-market-pages.md): whether they're due, the open run and the pages
    || private.capture_market_plan(v_world, now());
  if v_unattended then
    -- the scan and the market pages: as for a normal key, unless the world's setting keeps them from the unattended key
    if not private.capture_unattended_allows(v_world, 'scan') then
      v_doc := v_doc || jsonb_build_object('scan_due', false, 'scan_open', null);
    end if;
    if not private.capture_unattended_allows(v_world, 'market') then
      v_doc := v_doc || jsonb_build_object('market_due', false, 'market_open', null, 'market_pages', '[]'::jsonb);
    end if;
    v_doc := v_doc || jsonb_build_object('unattended', true);
  end if;
  return v_doc;
end
$function$;

do $describe$
declare d text := obj_description('public.capture_airlines(text)'::regprocedure, 'pg_proc');
begin
  if position('unattended' in coalesce(d, '')) = 0 then
    execute format('comment on function public.capture_airlines(text) is %L', coalesce(d, '')
      || ' Since 10 Nov (spec docs/specs/2026-11-10-unattended-capture.md §1), with the unattended capture''s key (capture_keys.unattended) it also answers unattended true, salary_above_average_pct null while the world''s unattended_salaries is false, the scan not due (scan_open null) while unattended_scan is false, and the market pages not due (market_open null, no pages) while unattended_market is false; a normal key answers as before.');
  end if;
end
$describe$;

-- The fares, the aircraft evaluation, the world scan and the market pages: each function as it stands, with the
-- unattended key's refusal after the key's check (grants and settings kept: create or replace keeps the grants, and each
-- states its own settings).

CREATE OR REPLACE FUNCTION public.capture_fare_actions(p_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
 SET statement_timeout TO '30s'
 SET plan_cache_mode TO 'force_custom_plan'
AS $function$
declare v_world bigint;
begin
  v_world := private.capture_key_world(p_key);
  if v_world is null then return jsonb_build_object('ok', false, 'error', 'bad key'); end if;
  -- the unattended capture's key reads only (since 10 Nov, spec docs/specs/2026-11-10-unattended-capture.md §1): fares are
  -- never changed on a schedule (manual §5), so it is refused as a wrong key is
  if private.capture_key_unattended(p_key) then return jsonb_build_object('ok', false, 'error', 'bad key'); end if;
  return jsonb_build_object('ok', true, 'world', (select w.name from public.worlds w where w.id = v_world))
         || private.capture_fare_actions_doc(v_world, now());
end
$function$;

do $describe$
declare d text := obj_description('public.capture_fare_actions(text)'::regprocedure, 'pg_proc');
begin
  if position('unattended' in coalesce(d, '')) = 0 then
    execute format('comment on function public.capture_fare_actions(text) is %L', coalesce(d, '')
      || ' Since 10 Nov (spec docs/specs/2026-11-10-unattended-capture.md §1) it refuses the unattended capture''s key (capture_keys.unattended) as it refuses a wrong one: fares are never changed on a schedule (manual §5).');
  end if;
end
$describe$;

CREATE OR REPLACE FUNCTION public.capture_fare_actions_by_airline(p_key text, p_game_id integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
 SET statement_timeout TO '30s'
 SET plan_cache_mode TO 'force_custom_plan'
AS $function$
declare v_world bigint; v_doc jsonb;
begin
  v_world := private.capture_key_world(p_key);
  if v_world is null then return jsonb_build_object('ok', false, 'error', 'bad key'); end if;
  -- the unattended capture's key reads only (since 10 Nov, spec docs/specs/2026-11-10-unattended-capture.md §1): fares are
  -- never changed on a schedule (manual §5), so it is refused as a wrong key is
  if private.capture_key_unattended(p_key) then return jsonb_build_object('ok', false, 'error', 'bad key'); end if;
  if p_game_id is null then
    -- the list: our active airlines of the world in display order, with no fare ladder worked out (it answers at once)
    return jsonb_build_object('ok', true, 'world', (select w.name from public.worlds w where w.id = v_world),
             'as_of', private.fig_ts(now()),
             'airlines', coalesce((select jsonb_agg(jsonb_build_object('game_id', a.game_id, 'name', coalesce(a.public_name, a.planner_name, a.game_name),
                                                                       'game_name', a.game_name, 'code', a.iata_code)
                                                    order by a.position nulls last, a.id)
                                     from public.airlines a join public.groups g on g.id = a.group_id and g.world_id = a.world_id
                                    where a.world_id = v_world and a.active and g.kind = 'ours'), '[]'::jsonb));
  end if;
  v_doc := private.capture_fare_actions_doc(v_world, now(), p_game_id);
  if jsonb_array_length(v_doc -> 'airlines') = 0 then return jsonb_build_object('ok', false, 'error', 'no such airline of ours: ' || p_game_id); end if;
  return jsonb_build_object('ok', true, 'world', (select w.name from public.worlds w where w.id = v_world)) || v_doc;
end
$function$;

do $describe$
declare d text := obj_description('public.capture_fare_actions_by_airline(text, integer)'::regprocedure, 'pg_proc');
begin
  if position('unattended' in coalesce(d, '')) = 0 then
    execute format('comment on function public.capture_fare_actions_by_airline(text, integer) is %L', coalesce(d, '')
      || ' Since 10 Nov (spec docs/specs/2026-11-10-unattended-capture.md §1) it refuses the unattended capture''s key (capture_keys.unattended) as it refuses a wrong one: fares are never changed on a schedule (manual §5).');
  end if;
end
$describe$;

CREATE OR REPLACE FUNCTION public.capture_eval_runs(p_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_world bigint; v_types jsonb;
begin
  v_world := private.capture_key_world(p_key);
  if v_world is null then return jsonb_build_object('ok', false, 'error', 'bad key'); end if;
  -- the unattended capture's key reads only (since 10 Nov, spec docs/specs/2026-11-10-unattended-capture.md §1): the aircraft
  -- evaluation is run by hand, so it is refused as a wrong key is
  if private.capture_key_unattended(p_key) then return jsonb_build_object('ok', false, 'error', 'bad key'); end if;
  select s.value into v_types from public.settings s
   where s.world_id = v_world and s.airline_id is null and s.key = 'aircraft_eval_types';
  if v_types is null or jsonb_typeof(v_types) <> 'array' or jsonb_array_length(v_types) = 0 then
    return jsonb_build_object('ok', false, 'error', 'no aircraft_eval_types setting in this world');
  end if;
  return jsonb_build_object(
    'ok', true,
    'world', (select w.name from public.worlds w where w.id = v_world),
    'types', v_types,
    'total', (select count(*) from public.aircraft_eval_runs r where r.world_id = v_world),
    'done', (select count(*) from public.aircraft_eval_runs r where r.world_id = v_world and r.done_at is not null),
    'runs', coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'pass', r.pass, 'seq', r.seq, 'from', r.from_code,
                                                          'to', r.to_code, 'seat', r.seat) order by r.pass, r.seq)
                        from public.aircraft_eval_runs r where r.world_id = v_world and r.done_at is null), '[]'::jsonb));
end
$function$;

do $describe$
declare d text := obj_description('public.capture_eval_runs(text)'::regprocedure, 'pg_proc');
begin
  if position('unattended' in coalesce(d, '')) = 0 then
    execute format('comment on function public.capture_eval_runs(text) is %L', coalesce(d, '')
      || ' Since 10 Nov (spec docs/specs/2026-11-10-unattended-capture.md §1) it refuses the unattended capture''s key (capture_keys.unattended) as it refuses a wrong one.');
  end if;
end
$describe$;

CREATE OR REPLACE FUNCTION public.capture_eval_result(p_key text, p_run bigint, p_doc jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_world bigint; v_seat text; v_types jsonb; v_rows jsonb; v_bad text; v_n integer;
  c_figs constant text[] := array['flights_week', 'seats', 'fuel', 'handling', 'atc', 'landing', 'maintenance', 'capital',
                                  'crew', 'fixed_total', 'per_seat', 'profit_50', 'profit_60', 'profit_70', 'profit_80',
                                  'profit_90', 'profit_100', 'margin_50', 'margin_60', 'margin_70', 'margin_80', 'margin_90',
                                  'margin_100'];
begin
  v_world := private.capture_key_world(p_key);
  if v_world is null then return jsonb_build_object('ok', false, 'error', 'bad key'); end if;
  -- the unattended capture's key reads only (since 10 Nov, spec docs/specs/2026-11-10-unattended-capture.md §1): the aircraft
  -- evaluation is run by hand, so it is refused as a wrong key is
  if private.capture_key_unattended(p_key) then return jsonb_build_object('ok', false, 'error', 'bad key'); end if;
  select r.seat into v_seat from public.aircraft_eval_runs r where r.id = p_run and r.world_id = v_world;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'run ' || coalesce(p_run::text, '(none)') || ' isn''t on this world''s run list');
  end if;
  select s.value into v_types from public.settings s
   where s.world_id = v_world and s.airline_id is null and s.key = 'aircraft_eval_types';
  if v_types is null or jsonb_typeof(v_types) <> 'array' or jsonb_array_length(v_types) = 0 then
    return jsonb_build_object('ok', false, 'error', 'no aircraft_eval_types setting in this world');
  end if;
  if p_doc is null or jsonb_typeof(p_doc) <> 'object' or jsonb_typeof(p_doc -> 'rows') is distinct from 'array' then
    return jsonb_build_object('ok', false, 'error', 'the result has no rows');
  end if;
  if coalesce(btrim(p_doc ->> 'from_name'), '') = '' or coalesce(btrim(p_doc ->> 'to_name'), '') = '' then
    return jsonb_build_object('ok', false, 'error', 'the result doesn''t name the route''s two airports');
  end if;
  if jsonb_typeof(p_doc -> 'settings') is distinct from 'object' or p_doc -> 'settings' ->> 'seat' is distinct from v_seat then
    return jsonb_build_object('ok', false, 'error', 'the result''s seat is ' || coalesce(p_doc -> 'settings' ->> 'seat', 'not given')
                                                    || ', the run''s ' || v_seat);
  end if;
  v_rows := p_doc -> 'rows';

  -- each row: an object with its type's name, can_operate true or false, the game's type id a whole number or null,
  -- and its cells as a list
  select string_agg('row ' || e.i, ', ' order by e.i) into v_bad
    from jsonb_array_elements(v_rows) with ordinality as e(x, i)
   where jsonb_typeof(e.x) <> 'object' or jsonb_typeof(e.x -> 'type_name') is distinct from 'string'
      or btrim(e.x ->> 'type_name') = '' or jsonb_typeof(e.x -> 'can_operate') is distinct from 'boolean'
      or jsonb_typeof(e.x -> 'cells') is distinct from 'array'
      or coalesce(jsonb_typeof(e.x -> 'game_type_id'), 'null') not in ('null', 'number')
      or (jsonb_typeof(e.x -> 'game_type_id') = 'number' and (e.x ->> 'game_type_id') !~ '^[0-9]+$');
  if v_bad is not null then
    return jsonb_build_object('ok', false, 'error', v_bad || ': needs type_name, can_operate (true or false), cells and a whole game_type_id or none');
  end if;
  select string_agg(t.n, ', ' order by t.n) into v_bad
    from (select e.x ->> 'type_name' as n from jsonb_array_elements(v_rows) e(x) group by 1 having count(*) > 1) t;
  if v_bad is not null then return jsonb_build_object('ok', false, 'error', 'a type twice in the result: ' || v_bad); end if;

  -- every type of the setting has its row
  select string_agg(t.n, ', ' order by t.i) into v_bad
    from jsonb_array_elements_text(v_types) with ordinality as t(n, i)
   where not exists (select 1 from jsonb_array_elements(v_rows) e(x) where e.x ->> 'type_name' = t.n);
  if v_bad is not null then return jsonb_build_object('ok', false, 'error', 'the result has no row for ' || v_bad); end if;

  -- a type that can fly: every figure a number; one that can't: none
  select string_agg(e.x ->> 'type_name' || ': ' || f.k, ', ' order by e.i, f.j) into v_bad
    from jsonb_array_elements(v_rows) with ordinality as e(x, i)
    cross join unnest(c_figs) with ordinality as f(k, j)
   where (e.x ->> 'can_operate')::boolean and jsonb_typeof(e.x -> f.k) is distinct from 'number';
  if v_bad is not null then return jsonb_build_object('ok', false, 'error', 'not a number: ' || v_bad); end if;
  select string_agg(e.x ->> 'type_name' || ': ' || f.k, ', ' order by e.i, f.j) into v_bad
    from jsonb_array_elements(v_rows) with ordinality as e(x, i)
    cross join unnest(c_figs) with ordinality as f(k, j)
   where not (e.x ->> 'can_operate')::boolean and coalesce(jsonb_typeof(e.x -> f.k), 'null') <> 'null';
  if v_bad is not null then return jsonb_build_object('ok', false, 'error', 'a figure for a type that cannot operate: ' || v_bad); end if;

  -- replace any earlier result for the run
  delete from public.aircraft_eval_results r where r.run_id = p_run;
  insert into public.aircraft_eval_results (run_id, type_name, game_type_id, can_operate, message, flights_week, seats, fuel,
                                            handling, atc, landing, maintenance, capital, crew, fixed_total, per_seat,
                                            profit_50, profit_60, profit_70, profit_80, profit_90, profit_100,
                                            margin_50, margin_60, margin_70, margin_80, margin_90, margin_100, cells)
  select p_run, btrim(x ->> 'type_name'), (x ->> 'game_type_id')::bigint, (x ->> 'can_operate')::boolean,
         nullif(btrim(x ->> 'message'), ''),
         (x ->> 'flights_week')::numeric, (x ->> 'seats')::numeric, (x ->> 'fuel')::numeric, (x ->> 'handling')::numeric,
         (x ->> 'atc')::numeric, (x ->> 'landing')::numeric, (x ->> 'maintenance')::numeric, (x ->> 'capital')::numeric,
         (x ->> 'crew')::numeric, (x ->> 'fixed_total')::numeric, (x ->> 'per_seat')::numeric,
         (x ->> 'profit_50')::numeric, (x ->> 'profit_60')::numeric, (x ->> 'profit_70')::numeric,
         (x ->> 'profit_80')::numeric, (x ->> 'profit_90')::numeric, (x ->> 'profit_100')::numeric,
         (x ->> 'margin_50')::numeric, (x ->> 'margin_60')::numeric, (x ->> 'margin_70')::numeric,
         (x ->> 'margin_80')::numeric, (x ->> 'margin_90')::numeric, (x ->> 'margin_100')::numeric,
         x -> 'cells'
    from jsonb_array_elements(v_rows) e(x);
  get diagnostics v_n = row_count;
  update public.aircraft_eval_runs r
     set from_name = btrim(p_doc ->> 'from_name'), to_name = btrim(p_doc ->> 'to_name'), settings = p_doc -> 'settings',
         done_at = clock_timestamp()
   where r.id = p_run;
  return jsonb_build_object(
    'ok', true, 'run', p_run, 'saved', v_n,
    'done', (select count(*) from public.aircraft_eval_runs r where r.world_id = v_world and r.done_at is not null),
    'total', (select count(*) from public.aircraft_eval_runs r where r.world_id = v_world));
end
$function$;

do $describe$
declare d text := obj_description('public.capture_eval_result(text, bigint, jsonb)'::regprocedure, 'pg_proc');
begin
  if position('unattended' in coalesce(d, '')) = 0 then
    execute format('comment on function public.capture_eval_result(text, bigint, jsonb) is %L', coalesce(d, '')
      || ' Since 10 Nov (spec docs/specs/2026-11-10-unattended-capture.md §1) it refuses the unattended capture''s key (capture_keys.unattended) as it refuses a wrong one.');
  end if;
end
$describe$;

CREATE OR REPLACE FUNCTION public.capture_scan(p_key text, p_kind text, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET statement_timeout TO '30s'
 SET plan_cache_mode TO 'force_custom_plan'
AS $function$
declare v_world bigint; v_scan bigint; v_res jsonb;
  v_actor text := current_setting('equinox.actor', true); v_detail text := current_setting('equinox.actor_detail', true);
begin
  v_world := private.capture_key_world(p_key);
  if v_world is null then return jsonb_build_object('ok', false, 'error', 'bad key'); end if;
  -- the unattended capture's key (since 10 Nov, spec docs/specs/2026-11-10-unattended-capture.md §1): refused as a wrong key
  -- is while the world's unattended_scan is false
  if not private.capture_unattended_allows(v_world, 'scan') then
    if private.capture_key_unattended(p_key) then return jsonb_build_object('ok', false, 'error', 'bad key'); end if;
  end if;
  if p_kind is null or p_kind not in ('start', 'airline', 'airport', 'finish', 'fleet') then
    return jsonb_build_object('ok', false, 'error', 'bad kind');
  end if;
  perform set_config('equinox.actor', coalesce(nullif(v_actor, ''), 'capture'), true),
          set_config('equinox.actor_detail', coalesce(nullif(v_detail, ''), 'capture_scan'), true);
  begin
    if p_kind = 'start' then
      -- one scan at a time: a capture run twice within the hour carries on with the scan it started
      perform pg_advisory_xact_lock(hashtext('equinox.capture_scan'), v_world::int);
      v_scan := private.scan_open(v_world, now());
      if v_scan is not null then
        v_res := jsonb_build_object('ok', true, 'snapshot_id', v_scan, 'carried_on', true);
      else
        v_res := private.scan_ingest(v_world, 'start', p_payload) || jsonb_build_object('ok', true, 'carried_on', false);
      end if;
    else
      -- only a scan of the key's world
      select s.id into v_scan from public.game_scans s
       where s.id = (p_payload ->> 'snapshot_id')::bigint and s.world_id = v_world;
      if v_scan is null then
        v_res := jsonb_build_object('ok', false, 'error', 'no such scan in this capture key''s world: ' || coalesce(p_payload ->> 'snapshot_id', '(none)'));
      else
        v_res := private.scan_ingest(v_world, p_kind, p_payload) || jsonb_build_object('snapshot_id', v_scan);
      end if;
    end if;
  exception when others then
    -- a payload that doesn't read is refused, writing nothing, and the scan carries on with the next page
    v_res := jsonb_build_object('ok', false, 'error', sqlerrm);
  end;
  perform set_config('equinox.actor', coalesce(v_actor, ''), true), set_config('equinox.actor_detail', coalesce(v_detail, ''), true);
  return v_res;
end
$function$;

do $describe$
declare d text := obj_description('public.capture_scan(text, text, jsonb)'::regprocedure, 'pg_proc');
begin
  if position('unattended' in coalesce(d, '')) = 0 then
    execute format('comment on function public.capture_scan(text, text, jsonb) is %L', coalesce(d, '')
      || ' Since 10 Nov (spec docs/specs/2026-11-10-unattended-capture.md §1) it refuses the unattended capture''s key (capture_keys.unattended) as it refuses a wrong one while the world''s unattended_scan setting is false.');
  end if;
end
$describe$;

CREATE OR REPLACE FUNCTION public.capture_market(p_key text, p_kind text, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET statement_timeout TO '30s'
 SET plan_cache_mode TO 'force_custom_plan'
AS $function$
declare v_world bigint; v_run bigint; v_res jsonb;
  v_actor text := current_setting('equinox.actor', true); v_detail text := current_setting('equinox.actor_detail', true);
begin
  v_world := private.capture_key_world(p_key);
  if v_world is null then return jsonb_build_object('ok', false, 'error', 'bad key'); end if;
  -- the unattended capture's key (since 10 Nov, spec docs/specs/2026-11-10-unattended-capture.md §1): refused as a wrong key
  -- is while the world's unattended_market is false
  if not private.capture_unattended_allows(v_world, 'market') then
    if private.capture_key_unattended(p_key) then return jsonb_build_object('ok', false, 'error', 'bad key'); end if;
  end if;
  if p_kind is null or p_kind not in ('start', 'page', 'finish') then
    return jsonb_build_object('ok', false, 'error', 'bad kind');
  end if;
  perform set_config('equinox.actor', coalesce(nullif(v_actor, ''), 'capture'), true),
          set_config('equinox.actor_detail', coalesce(nullif(v_detail, ''), 'capture_market'), true);
  begin
    if p_kind = 'start' then
      -- one run at a time: a capture run twice within the hour carries on with the run it started; one left open longer
      -- is stopped first
      perform pg_advisory_xact_lock(hashtext('equinox.capture_market'), v_world::int);
      perform private.market_stop_unfinished(v_world, now());
      v_run := private.market_open(v_world, now());
      if v_run is not null then
        v_res := jsonb_build_object('ok', true, 'run_id', v_run, 'carried_on', true);
      else
        v_res := private.market_ingest(v_world, 'start', coalesce(p_payload, '{}'::jsonb)) || jsonb_build_object('ok', true, 'carried_on', false);
      end if;
    else
      v_res := jsonb_build_object('ok', true) || private.market_ingest(v_world, p_kind, p_payload)
               || jsonb_build_object('run_id', (p_payload ->> 'run_id')::bigint);
    end if;
  exception when others then
    -- a payload that doesn't read is refused, writing nothing, and the run carries on with the next page
    v_res := jsonb_build_object('ok', false, 'error', sqlerrm);
  end;
  perform set_config('equinox.actor', coalesce(v_actor, ''), true), set_config('equinox.actor_detail', coalesce(v_detail, ''), true);
  return v_res;
end
$function$;

do $describe$
declare d text := obj_description('public.capture_market(text, text, jsonb)'::regprocedure, 'pg_proc');
begin
  if position('unattended' in coalesce(d, '')) = 0 then
    execute format('comment on function public.capture_market(text, text, jsonb) is %L', coalesce(d, '')
      || ' Since 10 Nov (spec docs/specs/2026-11-10-unattended-capture.md §1) it refuses the unattended capture''s key (capture_keys.unattended) as it refuses a wrong one while the world''s unattended_market setting is false.');
  end if;
end
$describe$;

-- ============================================================ 6. the dispatch
create extension if not exists pg_net with schema extensions;

create or replace function private.capture_dispatch_answer()
returns jsonb
language plpgsql
set search_path to ''
as $function$
declare r record; v_resp record; v_noted int := 0; v_waiting int := 0; v_words text;
begin
  -- each dispatch of the last two days that posted and has no answer noted yet
  for r in select j.id, (j.details ->> 'request_id')::bigint as request_id, j.started_at, j.note
             from public.job_runs j
            where j.job = 'capture_dispatch' and j.details ? 'request_id' and not j.details ? 'answer'
              and j.started_at > now() - interval '2 days'
            order by j.started_at, j.id
  loop
    select x.status_code, x.content, x.timed_out, x.error_msg into v_resp
      from net._http_response x where x.id = r.request_id;
    if not found then
      -- pg_net keeps an answer 6 hours: older than that, it's gone; younger, it hasn't come yet
      if r.started_at < now() - interval '6 hours' then
        update public.job_runs j
           set note = coalesce(r.note, '') || ' · GitHub''s answer was no longer kept (pg_net keeps 6 hours)',
               details = j.details || jsonb_build_object('answer', null)
         where j.id = r.id;
        v_noted := v_noted + 1;
      else
        v_waiting := v_waiting + 1;
      end if;
      continue;
    end if;
    if v_resp.status_code = 204 then
      update public.job_runs j
         set note = 'GitHub started the unattended capture (204; request ' || r.request_id || ')',
             details = j.details || jsonb_build_object('answer', 204)
       where j.id = r.id;
    else
      v_words := case when v_resp.status_code is not null
                      then 'GitHub answered ' || v_resp.status_code || ': ' || left(coalesce(v_resp.content, ''), 200)
                      when coalesce(v_resp.timed_out, false) then 'GitHub didn''t answer in time: ' || left(coalesce(v_resp.error_msg, 'timed out'), 200)
                      else 'GitHub couldn''t be reached: ' || left(coalesce(v_resp.error_msg, 'no answer'), 200) end;
      update public.job_runs j
         set status = 'failed', note = v_words,
             details = j.details || jsonb_build_object('answer', v_resp.status_code, 'timed_out', v_resp.timed_out)
       where j.id = r.id;
    end if;
    v_noted := v_noted + 1;
  end loop;
  return jsonb_build_object('noted', v_noted, 'waiting', v_waiting);
end
$function$;

create or replace function private.capture_dispatch(p_at timestamptz default null)
returns jsonb
language plpgsql
set search_path to ''
as $function$
declare
  -- GitHub's address for starting the job, and this project's own address: the dispatch posts only from the live project
  c_url constant text := 'https://api.github.com/repos/GiteshJain/equinox-backups/actions/workflows/capture.yml/dispatches';
  c_project constant text := 'https://ulecwsyedvwcxgdzmhoq.supabase.co';
  v_at timestamptz := coalesce(p_at, now());
  w bigint; v_token text; v_project text; v_last timestamptz; v_scan timestamptz; v_req bigint;
  v_status text; v_note text; v_details jsonb; v_answers jsonb;
begin
  select x.id into w from public.worlds x where x.is_default order by x.id limit 1;
  begin
    -- the last dispatch's answer, if it hasn't been noted yet
    v_answers := private.capture_dispatch_answer();
    select s.decrypted_secret into v_token from vault.decrypted_secrets s
     where s.name = 'github_dispatch_token' order by s.created_at desc limit 1;
    select s.decrypted_secret into v_project from vault.decrypted_secrets s
     where s.name = 'project_url' order by s.created_at desc limit 1;
    -- the latest capture page (raw pages and market pages), and a world scan still open within the hour
    select max(t) into v_last
      from (select max(r.captured_at) as t from public.game_capture_raw r where r.world_id = w and r.captured_at <= v_at
            union all
            select max(m.read_at) from public.market_reads m where m.world_id = w and m.read_at <= v_at) x;
    select max(s.taken_at) into v_scan from public.game_scans s
     where s.world_id = w and s.status not in ('done', 'stopped') and s.taken_at <= v_at and s.taken_at > v_at - interval '1 hour';
    if coalesce(btrim(v_token), '') = '' then
      v_status := 'failed'; v_note := 'no GitHub token in the vault';
    elsif rtrim(btrim(coalesce(v_project, '')), '/') <> c_project then
      v_status := 'failed';
      v_note := 'not the live project: the vault''s project_url is ' || coalesce(nullif(btrim(v_project), ''), 'missing') || ', not ' || c_project
                || '; nothing posted';
    elsif v_last > v_at - interval '20 minutes' or v_scan is not null then
      v_status := 'ok';
      v_note := 'skipped: a capture is running (' || case when v_scan is not null and (v_last is null or v_last <= v_at - interval '20 minutes')
                                                          then 'a world scan open since ' || to_char(v_scan at time zone 'UTC', 'HH24:MI') || ' UTC'
                                                          else 'a page at ' || to_char(v_last at time zone 'UTC', 'HH24:MI') || ' UTC' end || ')';
      v_details := jsonb_build_object('skipped', true, 'last_page_at', private.fig_ts(v_last), 'scan_open_since', private.fig_ts(v_scan));
    else
      v_req := net.http_post(
        url := c_url,
        body := jsonb_build_object('ref', 'main'),
        params := '{}'::jsonb,
        headers := jsonb_build_object('Accept', 'application/vnd.github+json', 'Authorization', 'Bearer ' || btrim(v_token),
                                      'X-GitHub-Api-Version', '2022-11-28', 'User-Agent', 'equinox-capture-dispatch',
                                      'Content-Type', 'application/json'),
        timeout_milliseconds := 10000);
      v_status := 'ok';
      v_note := 'asked GitHub to start the unattended capture (request ' || v_req || '); its answer is noted at :40';
      v_details := jsonb_build_object('request_id', v_req);
    end if;
  exception when others then
    v_status := 'failed'; v_note := 'the dispatch failed: ' || sqlerrm; v_details := null;
  end;
  perform private.job_run_add('capture_dispatch', w, v_at, v_status, v_note,
                              coalesce(v_details, '{}'::jsonb) || jsonb_build_object('answers_noted', v_answers -> 'noted'));
  return jsonb_build_object('status', v_status, 'note', v_note, 'request_id', v_req);
end
$function$;

-- ============================================================ 7. the schedule
create or replace function private.schedule_jobs()
returns jsonb
language plpgsql
set search_path to ''
as $function$
begin
  perform cron.schedule('equinox-snapshot-fallback', '0 10 * * *', 'select private.job_snapshot_fallback()');
  perform cron.schedule('equinox-cleanup', '20 10 * * *', 'select private.job_cleanup()');
  -- the unattended capture (since 10 Nov, spec docs/specs/2026-11-10-unattended-capture.md §1): the start at 09:30 and
  -- 21:30 UTC, and GitHub's answer noted ten minutes later
  perform cron.schedule('equinox-capture-dispatch', '30 9,21 * * *', 'select private.capture_dispatch()');
  perform cron.schedule('equinox-capture-dispatch-answer', '40 9,21 * * *', 'select private.capture_dispatch_answer()');
  return (select jsonb_agg(jsonb_build_object('job', j.jobname, 'schedule', j.schedule, 'command', j.command, 'active', j.active)
                           order by j.jobname)
            from cron.job j where j.jobname like 'equinox-%');
end
$function$;

select private.schedule_jobs();

-- ============================================================ 8. the Systems board
CREATE OR REPLACE FUNCTION public.system_status(p_world_id bigint DEFAULT NULL::bigint, p_as_of timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare w bigint; v_at timestamptz := coalesce(p_as_of, now()); v_month timestamptz; v_snap jsonb; v_job jsonb; v_fb timestamptz;
  v_backup jsonb; v_good jsonb; v_arch jsonb; v_clean jsonb; v_scan jsonb; v_stopped jsonb; v_market jsonb; v_un jsonb; v_db bigint; v_pdf bigint; v_site bigint;
begin
  if not private.caller_is_staff() then raise exception 'only planner staff can read the systems board' using errcode = '42501'; end if;
  w := private.fig_world(p_world_id);
  v_month := date_trunc('month', v_at at time zone 'UTC') at time zone 'UTC';

  -- the daily snapshot: the latest capture day in the daily history, and how it was taken
  select jsonb_build_object('day', x.day, 'source', x.source, 'complete', x.complete, 'taken_at', private.fig_ts(x.taken_at), 'airlines', x.airlines)
    into v_snap
    from (select ad.day, string_agg(distinct ad.source, ', ') as source, bool_and(ad.complete) as complete, max(ad.taken_at) as taken_at,
                 count(*)::int as airlines
            from public.airline_days ad
           where ad.world_id = w and ad.taken_at <= v_at
           group by ad.day order by ad.day desc limit 1) x;
  select jsonb_build_object('job', j.job, 'status', j.status, 'at', private.fig_ts(j.started_at), 'note', left(j.note, 300))
    into v_job
    from public.job_runs j
   where j.job in ('snapshot', 'snapshot_fallback') and (j.world_id = w or j.world_id is null) and j.started_at <= v_at and j.status <> 'running'
   order by j.started_at desc, j.id desc limit 1;
  select max(j.started_at) into v_fb from public.job_runs j
   where j.job = 'snapshot_fallback' and (j.world_id = w or j.world_id is null) and j.started_at <= v_at;

  -- the nightly backup: its latest run, and the latest good copy (a good run passed its restore check)
  select jsonb_build_object('ran_at', private.fig_ts(b.ran_at), 'ok', b.ok, 'kind', b.kind, 'note', left(b.note, 300))
    into v_backup
    from public.backup_runs b where coalesce(b.kind, '') <> 'test' and b.ran_at <= v_at order by b.ran_at desc, b.id desc limit 1;
  select jsonb_build_object('ran_at', private.fig_ts(b.ran_at), 'bytes', b.bytes, 'tables', b.tables, 'rows', b.rows, 'files', b.files,
                            'object_key', b.object_key)
    into v_good
    from public.backup_runs b where coalesce(b.kind, '') <> 'test' and b.ok and b.ran_at <= v_at order by b.ran_at desc, b.id desc limit 1;

  -- the monthly archive: its runs this month, its latest run, and any table and month whose latest run failed
  select jsonb_build_object(
           'last_at', private.fig_ts(max(j.started_at)),
           'month', (v_at at time zone 'UTC')::date - (extract(day from v_at at time zone 'UTC')::int - 1),
           'runs_this_month', count(*) filter (where j.started_at >= v_month),
           'ok_this_month', count(*) filter (where j.started_at >= v_month and j.status = 'ok'),
           'rows_this_month', coalesce(sum((j.details ->> 'rows')::bigint) filter (where j.started_at >= v_month and j.status = 'ok'), 0),
           'failed', coalesce((select jsonb_agg(jsonb_build_object('table', f.details ->> 'table', 'month', f.for_month, 'at', private.fig_ts(f.started_at),
                                                                   'note', left(f.note, 200)) order by f.started_at)
                                 from (select distinct on (x.details ->> 'table', x.for_month) x.*
                                         from public.job_runs x
                                        where x.job = 'archive' and x.started_at <= v_at and x.status <> 'running'
                                        order by x.details ->> 'table', x.for_month, x.started_at desc, x.id desc) f
                                where f.status = 'failed'), '[]'::jsonb))
    into v_arch
    from public.job_runs j where j.job = 'archive' and j.started_at <= v_at and j.status <> 'running';

  -- the clean-ups: the latest run
  select jsonb_build_object('at', private.fig_ts(j.started_at), 'status', j.status, 'note', left(j.note, 300))
    into v_clean
    from public.job_runs j
   where j.job = 'cleanup' and (j.world_id = w or j.world_id is null) and j.started_at <= v_at and j.status <> 'running'
   order by j.started_at desc, j.id desc limit 1;

  -- the world scan: the latest that has its airport summary (as hub_progress() reads it)
  -- since 23 Oct (spec docs/specs/2026-10-23-rival-fleets.md §5) with the overview pages it read and failed
  select jsonb_build_object('taken_at', private.fig_ts(s.taken_at), 'week', s.week, 'status', s.status,
                            'fleet_pages', (select count(*) from public.scan_airline_profile p where p.scan_id = s.id and p.read_ok)::int,
                            'fleet_failed', (select count(*) from public.scan_airline_profile p where p.scan_id = s.id and not p.read_ok)::int)
    into v_scan
    from public.game_scans s
   where s.world_id = w and s.taken_at <= v_at and exists (select 1 from public.scan_airline_airports x where x.scan_id = s.id)
   order by s.taken_at desc, s.id desc limit 1;
  -- a scan that stopped part-way since the latest finished one (spec docs/specs/2026-10-21-tidy-ups.md §1): marked stopped
  -- when the next scan started, or left unfinished for over an hour (nothing carries it on: private.scan_open())
  select jsonb_build_object('id', s.id, 'taken_at', private.fig_ts(s.taken_at), 'status', s.status, 'note', left(s.note, 300))
         || private.scan_progress(s.id)
    into v_stopped
    from public.game_scans s
   where s.world_id = w and s.taken_at <= v_at
     and (s.status = 'stopped' or (s.status not in ('done', 'stopped') and s.taken_at <= v_at - interval '1 hour'))
     and s.taken_at > coalesce((select max(d.taken_at) from public.game_scans d where d.world_id = w and d.status = 'done' and d.taken_at <= v_at),
                               '-infinity'::timestamptz)
   order by s.taken_at desc, s.id desc limit 1;

  -- the market pages (spec docs/specs/2026-10-30-market-pages.md): the latest finished run, its age, pages and failed
  select jsonb_build_object('id', r.id, 'started_at', private.fig_ts(r.started_at), 'finished_at', private.fig_ts(r.finished_at),
                            'age_days', round((extract(epoch from v_at - r.finished_at) / 86400)::numeric, 1),
                            'pages_read', r.pages_read, 'pages_failed', r.pages_failed, 'note', left(r.note, 300))
    into v_market
    from public.market_runs r
   where r.world_id = w and r.status = 'done' and r.started_at <= v_at
   order by r.started_at desc, r.id desc limit 1;

  -- the unattended capture (since 10 Nov, spec docs/specs/2026-11-10-unattended-capture.md §3): Today's setting, its last
  -- run and last good run (job_runs, capture_unattended, written by the GitHub job) and the database's last start of it
  select jsonb_build_object(
           'warn_h', (select s.value from public.settings s where s.world_id = w and s.airline_id is null and s.key = 'capture_unattended_warn_h'),
           'last', (select jsonb_build_object('at', private.fig_ts(j.started_at), 'status', j.status, 'note', left(j.note, 300))
                      from public.job_runs j
                     where j.job = 'capture_unattended' and (j.world_id = w or j.world_id is null) and j.started_at <= v_at and j.status <> 'running'
                     order by j.started_at desc, j.id desc limit 1),
           'last_ok', (select jsonb_build_object('at', private.fig_ts(j.started_at), 'status', j.status, 'note', left(j.note, 300))
                         from public.job_runs j
                        where j.job = 'capture_unattended' and (j.world_id = w or j.world_id is null) and j.started_at <= v_at and j.status = 'ok'
                        order by j.started_at desc, j.id desc limit 1),
           'dispatch', (select jsonb_build_object('at', private.fig_ts(j.started_at), 'status', j.status, 'note', left(j.note, 300))
                          from public.job_runs j
                         where j.job = 'capture_dispatch' and (j.world_id = w or j.world_id is null) and j.started_at <= v_at and j.status <> 'running'
                         order by j.started_at desc, j.id desc limit 1))
    into v_un;

  -- usage the database can measure, each against its trigger (manual §1; #16, #17, #20): now, whatever the moment
  v_db := pg_database_size(current_database());
  select coalesce(sum(octet_length(r.pdf_b64)), 0) * 3 / 4 into v_pdf from public.site_reports r where r.pdf_b64 is not null;
  v_site := octet_length(public.site_public()::text);

  return jsonb_build_object(
    'world_id', w, 'as_of', private.fig_ts(v_at),
    'capture', private.fig_capture_status(w, v_at) -> 'airlines',
    'snapshot', coalesce(v_snap, '{}'::jsonb) || jsonb_build_object('last_run', v_job, 'fallback_at', private.fig_ts(v_fb)),
    'backup', jsonb_build_object('last', v_backup, 'last_good', v_good),
    'archive', v_arch,
    'cleanup', v_clean,
    'scan', v_scan,
    'scan_stopped', v_stopped,
    'market', v_market,
    'unattended', v_un,
    'usage', jsonb_build_array(
      jsonb_build_object('key', 'database', 'label', 'Database size', 'bytes', v_db, 'trigger_bytes', 350 * 1024 * 1024::bigint),
      jsonb_build_object('key', 'report_pdfs', 'label', 'Report PDFs', 'bytes', v_pdf, 'trigger_bytes', 50 * 1024 * 1024::bigint),
      jsonb_build_object('key', 'site_public', 'label', 'The website''s data', 'bytes', v_site, 'trigger_bytes', 500 * 1024::bigint)));
end
$function$;

do $describe$
declare d text := obj_description('public.system_status(bigint, timestamptz)'::regprocedure, 'pg_proc');
begin
  if position('unattended' in coalesce(d, '')) = 0 then
    execute format('comment on function public.system_status(bigint, timestamptz) is %L', coalesce(d, '')
      || ' Since 10 Nov (spec docs/specs/2026-11-10-unattended-capture.md §3) also unattended: warn_h (settings.capture_unattended_warn_h), the unattended capture''s last run and last ok run (job_runs, capture_unattended: at, status, note) and the dispatch''s last run (capture_dispatch).');
  end if;
end
$describe$;

-- ============================================================ access
-- The new functions: postgres only. The jobs run as postgres; Gitesh issues a key in the SQL editor, as postgres.
revoke all on function private.capture_key_issue(bigint, text, boolean), private.capture_key_unattended(text),
  private.capture_unattended_allows(bigint, text), private.capture_dispatch(timestamptz), private.capture_dispatch_answer()
  from public, anon, authenticated, service_role;

-- ============================================================ descriptions
comment on function private.capture_key_issue(bigint, text, boolean) is 'Issues a capture key (since 10 Nov; spec docs/specs/2026-11-10-unattended-capture.md §1): 32 random bytes as hex, stored only as its hash (extensions.crypt with a bf salt, as private.capture_key_world() checks it) in capture_keys with its world, label and whether it is the unattended capture''s; answers the key once, and it can''t be read again. postgres only: Gitesh runs it in Supabase''s SQL editor (select private.capture_key_issue(1, ''unattended (GitHub)'', true);) so the key never passes through a chat.';
comment on function private.capture_key_unattended(text) is 'Whether a capture key is the unattended capture''s (capture_keys.unattended; since 10 Nov): false for a normal key and for one that doesn''t match.';
comment on function private.capture_unattended_allows(bigint, text) is 'Whether the unattended capture may do something in a world (since 10 Nov): the world''s setting unattended_<p_what> (salaries, scan or market) is true; false without it.';
comment on function private.capture_dispatch(timestamp with time zone) is 'The unattended capture''s start (pg_cron equinox-capture-dispatch, 09:30 and 21:30 UTC; since 10 Nov, spec docs/specs/2026-11-10-unattended-capture.md §1): notes the last start''s answer (private.capture_dispatch_answer()), then asks GitHub to run the capture job in equinox-backups (POST .../actions/workflows/capture.yml/dispatches, {"ref": "main"}, through pg_net) with the vault''s github_dispatch_token. Posts nothing, writing a failed row, with no token in the vault or unless the vault''s project_url is this project''s address (so a restored copy, whose vault is empty, never posts); posts nothing, writing an ok row "skipped: a capture is running", when a capture page arrived in the last 20 minutes or a world scan is open within the hour. One job_runs row a run (capture_dispatch; ok with pg_net''s request id when the post was queued), failed with the error rather than raised. p_at: the run''s moment, default now (for the checks). postgres only.';
comment on function private.capture_dispatch_answer() is 'Notes GitHub''s answer to each start of the unattended capture (pg_cron equinox-capture-dispatch-answer, 09:40 and 21:40 UTC, and at each start; since 10 Nov): for each capture_dispatch row of the last two days that posted and has no answer yet, reads pg_net''s answer (net._http_response, kept 6 hours) and notes it on that row: 204 stays ok; any other status, a time-out or no answer makes the row failed, with the status and the first 200 characters of the answer. An answer older than 6 hours is gone, and the row says so. Answers how many it noted and how many are still waiting. postgres only.';
comment on function private.schedule_jobs() is 'Schedules the database jobs with pg_cron, by name, so it can run again safely: equinox-snapshot-fallback at 10:00 UTC (private.job_snapshot_fallback), equinox-cleanup at 10:20 UTC (private.job_cleanup) and, since 10 Nov, equinox-capture-dispatch at 09:30 and 21:30 UTC (private.capture_dispatch) and equinox-capture-dispatch-answer at 09:40 and 21:40 UTC (private.capture_dispatch_answer). Run by migrations 20261011150000_jobs and 20261110040000_unattended_capture, and again after a full restore (the backup copies no schedules). Answers with the jobs as the scheduler has them.';

select set_config('equinox.actor', '', true), set_config('equinox.actor_detail', '', true);

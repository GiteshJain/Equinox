-- The planner's figures stored after every capture, part 1: the database (11 Nov 2026; to-do 223; spec
-- docs/specs/2026-11-11-stored-figures.md §1, pull request 1 of 2; brief docs/briefs/2026-11-11-instant-planner.md,
-- option B).
--
-- Why: every figure the planner shows is worked out by the database when a screen asks for it: about 30 s and 5.4 MB of
-- text for all six airlines on a quiet database (11 Nov), so moving between screens waits on the database. The figures
-- change only with a capture (or a save), so after each capture the database works every one out once and stores the
-- answers; the planner (part 2) will read the stored set. This part stores them while the planner still reads live, so
-- the stored answers can be compared with the live ones on real captures before anything reads them.
--
-- Adds two tables, three settings in every world, five functions and one scheduled job; widens one rule; replaces two
-- functions with the same arguments (create or replace keeps their grants). Drops, renames and deletes nothing, so it can
-- be applied from the chat:
--   1. public.planner_figures: one row per stored answer (world, kind = the function's name, key = '' for a world-wide
--      figure, the airline id, '<airline id>:<days>' for route and aircraft profit, the route id for a route's page),
--      exactly what the function gives, with the moment it was worked out (passed as p_as_of), its generation and how
--      long it took. Only the latest set is kept: each refresh replaces rows in place.
--      public.planner_figures_state: one row per world: the generation the planner should load, when it was finished,
--      what it was worked out from (sources), the route pages done of the routes flown, and the last error.
--      Both: RLS on, one staff read rule, staff read only, nothing for anon; written only by the functions below.
--   2. Settings, world rows in every world, described: figures_capture_quiet_min 5 (a capture page within this many
--      minutes means a capture is running), figures_route_budget_s 40 (how long a minute's run may spend on route
--      pages), figures_landing_max_min 30 (the planner's landing page never stays longer than this through a capture;
--      read by part 2).
--   3. job_runs.job also takes figures (one row per stored set).
--   4. private.figures_capture_running(world, at): whether a capture is running (a capture page in the quiet window, a
--      world scan of the world started within the hour that is neither done nor stopped, a market run started within the
--      hour that is still open), what, since when, and its progress.
--      private.figures_sources(world): what a stored set depends on (the latest capture page's time, the latest finished
--      scan, the latest finished market run, the latest change_log row of the world).
--      private.figures_refresh(world, at, fail): the job (pg_cron equinox-figures, every minute). With a capture running,
--      nothing. When the capture, scan or market stamps moved (or there is no set yet), or only the planner tables did and
--      the last save is over a minute old: every figure of spec §1's list at one moment, each in its own sub-block (one
--      that fails keeps its previous answer and the rest go on), then generation, ready_at and sources together, in the
--      job's one transaction, so the planner never sees half a set; one job_runs row. Otherwise the route pages
--      (private.figures_routes()), never in the same run as a new set, so a new set is visible the moment it is done.
--      Overlap guard: a run that finds another still running skips (an advisory lock).
--      private.figures_routes(world, at): route pages (route_story()) of the flown routes whose stored page is older than
--      the set's capture, scan or market stamps, oldest first, within figures_route_budget_s, each on its own. A save
--      alone never redoes them.
--      public.planner_figures_status(world): staff, read with GET, light (works no figure out): the stored generation and
--      when it was ready, whether a capture is running (what, since when, its progress), whether a refresh is due or
--      under way, the route pages done of total, and the last error.
--   5. private.schedule_jobs() also schedules equinox-figures every minute, and is run here.
--   6. system_status()'s usage also lists the stored figures' size (planner_figures with its indexes and TOAST), amber
--      from 50 MB (the board marks amber at 70% of the trigger, so the trigger is 50 MB / 0.7).

select set_config('equinox.actor', 'migration', true),
       set_config('equinox.actor_detail', '20261111020000_stored_figures', true);

-- ============================================================ 1. the tables
create table public.planner_figures (
  world_id bigint not null references public.worlds (id),
  kind text not null check (kind ~ '^[a-z_]+$'),
  key text not null,
  answer jsonb not null,
  as_of timestamptz not null,
  generation bigint not null check (generation > 0),
  worked_ms integer not null check (worked_ms >= 0),
  primary key (world_id, kind, key)
);
-- world_id, the foreign key, is the primary key's first column: indexed

create table public.planner_figures_state (
  world_id bigint primary key references public.worlds (id),
  generation bigint not null default 0 check (generation >= 0),
  ready_at timestamptz,
  sources jsonb,
  refreshing_since timestamptz,
  routes_done integer not null default 0 check (routes_done >= 0),
  routes_total integer not null default 0 check (routes_total >= 0),
  last_error text,
  last_error_at timestamptz
);

alter table public.planner_figures enable row level security;
alter table public.planner_figures_state enable row level security;
create policy "staff read" on public.planner_figures for select to authenticated using ((select public.is_planner_user()));
create policy "staff read" on public.planner_figures_state for select to authenticated using ((select public.is_planner_user()));
revoke all on table public.planner_figures from public, anon, authenticated;
revoke all on table public.planner_figures_state from public, anon, authenticated;
grant select on table public.planner_figures to authenticated;
grant select on table public.planner_figures_state to authenticated;

comment on table public.planner_figures is 'The planner''s figures, stored after every capture (since 11 Nov; to-do 223, spec docs/specs/2026-11-11-stored-figures.md §1): one row per answer, exactly what the function gives when called with the planner''s arguments at as_of. Each world: airline_cards, growth_signals, hub_progress, route_loads, fleet_checks, cash_log and shared_pairs_status, and in the default world cabin_charges and market_service_checks (they take no world); each of our active airlines: airline_profit, cash_forecast (no orders), fare_changes, fare_plan_status, fare_ladder, fare_results, competition (its default limit), and route_profit and aircraft_profit for 1, 3 and 7 days; each flown route (rotations, not removed): route_story. Written only by private.figures_refresh() (the pg_cron job equinox-figures, every minute) and private.figures_routes(); only the latest set is kept, each refresh replacing rows in place (a figure that fails keeps its previous answer). Staff read it; planner_figures_status() says which generation is ready.';
comment on column public.planner_figures.world_id is 'The world the answer is for (a world-wide figure''s, or its airline''s or route''s)';
comment on column public.planner_figures.kind is 'The function that gives the answer, by its name: airline_cards, cash_forecast, route_profit, route_story and so on';
comment on column public.planner_figures.key is 'Which answer of that function: empty for a world-wide figure, the airline id (cash_forecast), <airline id>:<days> for route_profit and aircraft_profit (12:7), the route id for route_story';
comment on column public.planner_figures.answer is 'Exactly what the function gave, called with the planner''s arguments and as_of as p_as_of';
comment on column public.planner_figures.as_of is 'The moment it was worked out, passed to the function as p_as_of: the whole set''s moment for the main set, the route page''s own for route_story';
comment on column public.planner_figures.generation is 'The set it was written in (planner_figures_state.generation at the time); a figure that failed in a later set keeps its older generation, and a route page takes the set''s current generation';
comment on column public.planner_figures.worked_ms is 'How long the function took, in milliseconds';

comment on table public.planner_figures_state is 'Where the stored figures (planner_figures) stand, one row per world (since 11 Nov; to-do 223, spec docs/specs/2026-11-11-stored-figures.md §1): the generation the planner should load, when it was finished, what it was worked out from, the route pages done and the last error. Written only by private.figures_refresh() and private.figures_routes(); read by planner_figures_status() and staff.';
comment on column public.planner_figures_state.world_id is 'The world whose stored figures it describes';
comment on column public.planner_figures_state.generation is 'The set the planner should load: moves on by one each time a whole set is stored, in the same transaction as its rows (0 before the first)';
comment on column public.planner_figures_state.ready_at is 'When that set was finished';
comment on column public.planner_figures_state.sources is 'What the set was worked out from (private.figures_sources()): capture_at (the latest capture page''s time), scan_id (the latest finished world scan), market_id (the latest finished market run), change_id and change_at (the latest change_log row of the world: the planner tables); with as_of, the set''s moment, and routes_from, the moment of the latest set that a capture, scan or market run caused: route pages worked out before it are redone';
comment on column public.planner_figures_state.refreshing_since is 'When the refresh that stored the current set began (the set took ready_at minus this). A refresh still under way can''t be seen here, since its writes show only when it ends: planner_figures_status() reads that from the running job';
comment on column public.planner_figures_state.routes_done is 'Flown routes whose stored page is up to date with the set''s capture, scan and market stamps';
comment on column public.planner_figures_state.routes_total is 'Flown routes (with rotations, not removed)';
comment on column public.planner_figures_state.last_error is 'The latest failure: the figures that failed and kept their previous answer, a route page that failed, or a refresh that failed as a whole (nothing stored); cleared when a whole set is stored with no failure';
comment on column public.planner_figures_state.last_error_at is 'When last_error was written';

-- ============================================================ 2. the settings
insert into public.settings (world_id, airline_id, key, value, unit, description, since, reason)
select w.id, null, x.key, x.value, x.unit, x.description, date '2026-11-11', x.reason
  from public.worlds w
 cross join (values
   ('figures_capture_quiet_min', '5'::jsonb, 'minutes',
    'The stored figures (spec docs/specs/2026-11-11-stored-figures.md §1): a capture page (game_capture_raw) that arrived within this many '
    'minutes means a capture is running (private.figures_capture_running()), so the figures are not worked out yet: the job waits until '
    'the pages stop. A capture''s pages come seconds apart; the world scan and the market pages have their own runs.',
    'Spec docs/specs/2026-11-11-stored-figures.md §1 (to-do 223, option B): five minutes without a page ends a capture'),
   ('figures_route_budget_s', '40'::jsonb, 'seconds',
    'The stored figures (spec docs/specs/2026-11-11-stored-figures.md §1): how long one minute''s run of the job (pg_cron equinox-figures) '
    'may spend on route pages (route_story(), about 3 s each), oldest first; the rest wait for the next minute''s run.',
    'Spec docs/specs/2026-11-11-stored-figures.md §1: under a minute, so one run ends before the next starts'),
   ('figures_landing_max_min', '30'::jsonb, 'minutes',
    'The stored figures (spec docs/specs/2026-11-11-stored-figures.md §2): the planner''s landing page never stays longer than this through '
    'a capture; past it the planner opens on the last stored answers with a line saying why. Read by the planner.',
    'Spec docs/specs/2026-11-11-stored-figures.md §2: a capture with the world scan and the market pages takes about 20 minutes')
 ) as x(key, value, unit, description, reason)
on conflict on constraint settings_world_airline_key_key do nothing;

-- ============================================================ 3. job_runs takes the figures' job
alter table public.job_runs
  drop constraint job_runs_job_check,
  add constraint job_runs_job_check check (job in ('backup', 'snapshot', 'snapshot_fallback', 'cleanup', 'archive', 'adapter_mirror',
                                                   'adapter_check', 'capture_unattended', 'capture_dispatch', 'figures'));
comment on column public.job_runs.job is 'backup, snapshot, snapshot_fallback, cleanup or archive; since 10 Nov capture_dispatch (the database asking GitHub to start the unattended capture, 09:30 and 21:30 UTC) and capture_unattended (the unattended capture''s run, written by the GitHub job in equinox-backups); since 11 Nov figures (a set of the planner''s figures stored, private.figures_refresh()); adapter_mirror and adapter_check are the old adapter''s runs, until the clean-up (build pull request 14)';

do $describe$
declare d text := obj_description('public.job_runs'::regclass, 'pg_class');
begin
  if position('figures_refresh' in coalesce(d, '')) = 0 then
    execute format('comment on table public.job_runs is %L', coalesce(d, '')
      || ' Since 11 Nov also figures (spec docs/specs/2026-11-11-stored-figures.md): one row each time private.figures_refresh() stores a set of the planner''s figures, with why, how long it took and any figure that failed.');
  end if;
end
$describe$;

-- ============================================================ 4. the functions
create or replace function private.figures_capture_running(p_world bigint, p_at timestamptz default null)
returns jsonb
language plpgsql
stable
set search_path to ''
as $function$
declare
  w bigint := private.fig_world(p_world);
  v_at timestamptz := coalesce(p_at, now());
  v_quiet interval;
  v_last_at timestamptz; v_last_airline bigint; v_last_name text; v_last_kind text;
  v_burst timestamptz; v_done int; v_total int;
  v_scan_id bigint; v_scan_at timestamptz;
  v_market_id bigint; v_market_at timestamptz; v_market_read int; v_market_failed int; v_market_expected int;
  v_pages boolean; v_what text; v_stage timestamptz; v_since timestamptz;
begin
  v_quiet := coalesce((select (s.value #>> '{}')::numeric from public.settings s
                        where s.world_id = w and s.airline_id is null and s.key = 'figures_capture_quiet_min'), 5) * interval '1 minute';

  -- the latest capture page, and where its run of pages began (the first page after a gap longer than the quiet window)
  select r.captured_at, r.airline_id, r.airline, r.kind into v_last_at, v_last_airline, v_last_name, v_last_kind
    from public.game_capture_raw r
   where r.world_id = w and r.captured_at <= v_at
   order by r.captured_at desc, r.id desc limit 1;
  if v_last_at > v_at - interval '1 hour' then
    select max(x.t) into v_burst
      from (select r.captured_at as t, lag(r.captured_at) over (order by r.captured_at) as prev
              from public.game_capture_raw r
             where r.world_id = w and r.captured_at <= v_at and r.captured_at > v_at - interval '6 hours') x
     where x.prev is null or x.t - x.prev > v_quiet;
    select count(distinct r.airline_id) into v_done from public.game_capture_raw r
     where r.world_id = w and r.captured_at >= v_burst and r.captured_at <= v_at;
    select count(*) into v_total from public.airlines a join public.groups g on g.id = a.group_id and g.world_id = a.world_id
     where a.world_id = w and a.active and g.kind = 'ours';
    select coalesce(a.public_name, a.planner_name, a.game_name, v_last_name) into v_last_name from public.airlines a where a.id = v_last_airline;
  end if;
  v_pages := v_last_at > v_at - v_quiet;

  -- a world scan started within the hour that is neither done nor stopped, and a market run started within the hour that is open
  select s.id, s.taken_at into v_scan_id, v_scan_at from public.game_scans s
   where s.world_id = w and s.status not in ('done', 'stopped') and s.taken_at <= v_at and s.taken_at > v_at - interval '1 hour'
   order by s.taken_at desc, s.id desc limit 1;
  select m.id, m.started_at, m.pages_read, m.pages_failed, m.pages_expected
    into v_market_id, v_market_at, v_market_read, v_market_failed, v_market_expected
    from public.market_runs m
   where m.world_id = w and m.status = 'open' and m.started_at <= v_at and m.started_at > v_at - interval '1 hour'
   order by m.started_at desc, m.id desc limit 1;

  -- what is running: the latest stage (the market pages follow the scan, which follows the airlines' pages)
  v_what := case when v_market_id is not null then 'market pages' when v_scan_id is not null then 'world scan'
                 when coalesce(v_pages, false) then 'capture' end;
  v_stage := case v_what when 'market pages' then v_market_at when 'world scan' then v_scan_at when 'capture' then v_burst end;
  -- since when the whole capture has been running: its pages' start when they came within the hour
  v_since := case when v_what is not null then least(v_burst, v_scan_at, v_market_at) end;

  return jsonb_build_object(
    'running', v_what is not null,
    'what', v_what,
    'since', private.fig_ts(v_since),
    'stage_since', private.fig_ts(v_stage),
    'last_page_at', private.fig_ts(v_last_at),
    'quiet_min', round(extract(epoch from v_quiet) / 60, 1),
    'capture', case when v_burst is not null and v_what is not null then
                 jsonb_build_object('airlines_done', v_done, 'airlines_total', v_total, 'airline', v_last_name, 'kind', v_last_kind,
                                    'since', private.fig_ts(v_burst)) end,
    'scan', case when v_scan_id is not null then
              jsonb_build_object('id', v_scan_id, 'since', private.fig_ts(v_scan_at)) || private.scan_progress(v_scan_id) end,
    'market', case when v_market_id is not null then
                jsonb_build_object('id', v_market_id, 'since', private.fig_ts(v_market_at), 'pages_read', v_market_read,
                                   'pages_failed', v_market_failed, 'pages_expected', v_market_expected) end);
end
$function$;

create or replace function private.figures_sources(p_world bigint)
returns jsonb
language plpgsql
stable
set search_path to ''
as $function$
declare w bigint := private.fig_world(p_world); v_change_id bigint; v_change_at timestamptz;
begin
  -- the planner tables: every change to them is a change_log row (with its world, or none for countries and airports)
  select c.id, c.changed_at into v_change_id, v_change_at from public.change_log c
   where c.world_id = w or c.world_id is null
   order by c.id desc limit 1;
  return jsonb_build_object(
    'capture_at', private.fig_ts((select max(r.captured_at) from public.game_capture_raw r where r.world_id = w)),
    'scan_id', (select s.id from public.game_scans s where s.world_id = w and s.status = 'done' order by s.taken_at desc, s.id desc limit 1),
    'market_id', (select m.id from public.market_runs m where m.world_id = w and m.status = 'done' order by m.started_at desc, m.id desc limit 1),
    'change_id', v_change_id,
    'change_at', private.fig_ts(v_change_at));
end
$function$;

create or replace function private.figures_routes(p_world bigint default null, p_at timestamptz default null)
returns jsonb
language plpgsql
set search_path to ''
as $function$
declare
  v_at timestamptz := coalesce(p_at, now());
  w bigint; st public.planner_figures_state%rowtype; v_src jsonb; v_run jsonb; v_from timestamptz; v_budget interval;
  t0 timestamptz; t1 timestamptz; r record; v_answer jsonb; n_worked int; n_done int; n_total int; v_failed jsonb;
  v_out jsonb := '[]'::jsonb;
begin
  -- one run at a time (the same guard as private.figures_refresh(), which calls this holding it)
  if not pg_try_advisory_xact_lock(20261111, 223) then
    return jsonb_build_object('skipped', 'another run of the stored figures is under way');
  end if;
  for w in select x.id from public.worlds x
            where (p_world is not null and x.id = p_world)
               or (p_world is null and exists (select 1 from public.airlines a join public.groups g on g.id = a.group_id and g.world_id = a.world_id
                                                 where a.world_id = x.id and a.active and g.kind = 'ours'))
            order by x.id loop
    v_run := private.figures_capture_running(w, v_at);
    if (v_run ->> 'running')::boolean then
      v_out := v_out || jsonb_build_object('world_id', w, 'did', 'nothing', 'why', 'a capture is running (' || (v_run ->> 'what') || ')');
      continue;
    end if;
    select * into st from public.planner_figures_state s where s.world_id = w;
    if st.world_id is null or st.generation = 0 then
      v_out := v_out || jsonb_build_object('world_id', w, 'did', 'nothing', 'why', 'no stored set yet');
      continue;
    end if;
    v_src := private.figures_sources(w);
    if v_src -> 'capture_at' is distinct from st.sources -> 'capture_at' or v_src -> 'scan_id' is distinct from st.sources -> 'scan_id'
       or v_src -> 'market_id' is distinct from st.sources -> 'market_id' then
      v_out := v_out || jsonb_build_object('world_id', w, 'did', 'nothing', 'why', 'a new set is due first');
      continue;
    end if;
    v_from := (st.sources ->> 'routes_from')::timestamptz;
    v_budget := coalesce((select (s.value #>> '{}')::numeric from public.settings s
                           where s.world_id = w and s.airline_id is null and s.key = 'figures_route_budget_s'), 40) * interval '1 second';
    t0 := clock_timestamp(); n_worked := 0; v_failed := '[]'::jsonb;

    -- a route no longer flown keeps no page
    delete from public.planner_figures x
     where x.world_id = w and x.kind = 'route_story'
       and not exists (select 1 from public.routes ro
                        where ro.world_id = w and ro.id::text = x.key and not ro.removed
                          and exists (select 1 from public.rotations rt where rt.route_id = ro.id));

    -- the flown routes whose page is older than the set's capture, scan or market stamps (or not stored), oldest first
    for r in select ro.id from public.routes ro
               left join public.planner_figures x on x.world_id = w and x.kind = 'route_story' and x.key = ro.id::text
              where ro.world_id = w and not ro.removed and exists (select 1 from public.rotations rt where rt.route_id = ro.id)
                and (x.as_of is null or v_from is null or x.as_of < v_from)
              order by x.as_of nulls first, ro.id loop
      exit when clock_timestamp() - t0 >= v_budget;
      begin
        t1 := clock_timestamp();
        v_answer := public.route_story(r.id, v_at);
        insert into public.planner_figures as f (world_id, kind, key, answer, as_of, generation, worked_ms)
        values (w, 'route_story', r.id::text, v_answer, v_at, st.generation, round(extract(epoch from clock_timestamp() - t1) * 1000)::int)
        on conflict (world_id, kind, key) do update
          set answer = excluded.answer, as_of = excluded.as_of, generation = excluded.generation, worked_ms = excluded.worked_ms;
        n_worked := n_worked + 1;
      exception when others then
        v_failed := v_failed || jsonb_build_object('route_id', r.id, 'error', left(sqlerrm, 300));
      end;
    end loop;

    select count(*), count(*) filter (where x.as_of >= v_from) into n_total, n_done
      from public.routes ro
      left join public.planner_figures x on x.world_id = w and x.kind = 'route_story' and x.key = ro.id::text
     where ro.world_id = w and not ro.removed and exists (select 1 from public.rotations rt where rt.route_id = ro.id);
    update public.planner_figures_state s
       set routes_done = n_done, routes_total = n_total,
           last_error = case when jsonb_array_length(v_failed) > 0
                             then left(format('%s route page(s) failed and kept their previous page: %s', jsonb_array_length(v_failed),
                                              (select string_agg('route ' || (e ->> 'route_id') || ': ' || (e ->> 'error'), '; ' order by i)
                                                 from jsonb_array_elements(v_failed) with ordinality as x(e, i))), 2000)
                             else s.last_error end,
           last_error_at = case when jsonb_array_length(v_failed) > 0 then clock_timestamp() else s.last_error_at end
     where s.world_id = w;
    v_out := v_out || jsonb_build_object('world_id', w, 'did', 'route pages', 'worked', n_worked, 'failed', v_failed,
                                         'routes_done', n_done, 'routes_total', n_total,
                                         'worked_ms', round(extract(epoch from clock_timestamp() - t0) * 1000)::int);
  end loop;
  return jsonb_build_object('as_of', private.fig_ts(v_at), 'worlds', v_out);
end
$function$;

create or replace function private.figures_refresh(p_world bigint default null, p_at timestamptz default null, p_fail text default null)
returns jsonb
language plpgsql
set search_path to ''
set statement_timeout to '5min'
as $function$
declare
  v_at timestamptz := coalesce(p_at, now());
  w bigint; st public.planner_figures_state%rowtype; v_run jsonb; v_src jsonb; v_reason text; v_why text; v_moved text[];
  v_default boolean; v_gen bigint; v_keys text[]; v_failed jsonb; n_all int; n_ok int; n_done int; n_total int;
  f record; v_answer jsonb; t0 timestamptz; t1 timestamptz; v_routes_from text; v_err text; v_note text;
  v_main boolean := false; v_rest bigint[] := '{}'; v_out jsonb := '[]'::jsonb;
begin
  -- one run at a time: a run that finds another still under way skips (pg_cron starts one every minute)
  if not pg_try_advisory_xact_lock(20261111, 223) then
    return jsonb_build_object('skipped', 'another run of the stored figures is under way');
  end if;
  for w in select x.id from public.worlds x
            where (p_world is not null and x.id = p_world)
               or (p_world is null and exists (select 1 from public.airlines a join public.groups g on g.id = a.group_id and g.world_id = a.world_id
                                                 where a.world_id = x.id and a.active and g.kind = 'ours'))
            order by x.id loop
    -- 1. a capture running: nothing (planner_figures_status() says so)
    v_run := private.figures_capture_running(w, v_at);
    if (v_run ->> 'running')::boolean then
      v_out := v_out || jsonb_build_object('world_id', w, 'did', 'nothing', 'why', 'a capture is running (' || (v_run ->> 'what') || ')');
      continue;
    end if;

    -- 2. is a new set due? The capture, scan or market stamps moved, or only the planner tables did and the last save is
    --    more than a minute old
    v_src := private.figures_sources(w);
    select * into st from public.planner_figures_state s where s.world_id = w;
    v_reason := null; v_why := 'up to date';
    if st.world_id is null or st.generation = 0 then
      v_reason := 'first set';
    else
      v_moved := array_remove(array[
        case when v_src -> 'capture_at' is distinct from st.sources -> 'capture_at' then 'capture' end,
        case when v_src -> 'scan_id' is distinct from st.sources -> 'scan_id' then 'world scan' end,
        case when v_src -> 'market_id' is distinct from st.sources -> 'market_id' then 'market pages' end], null);
      if cardinality(v_moved) > 0 then
        v_reason := 'new ' || array_to_string(v_moved, ', ');
      elsif v_src -> 'change_id' is distinct from st.sources -> 'change_id' then
        if (v_src ->> 'change_at')::timestamptz <= v_at - interval '1 minute' then
          v_reason := 'planner saves';
        else
          v_why := 'a planner save under a minute old: waiting';
        end if;
      end if;
    end if;
    if v_reason is null then
      v_rest := v_rest || w;
      v_out := v_out || jsonb_build_object('world_id', w, 'did', 'nothing', 'why', v_why);
      continue;
    end if;

    -- 3. the whole set at one moment (v_at), each figure on its own; then generation, ready_at and sources together. All in
    --    this one transaction, so the planner never sees half a set
    t0 := clock_timestamp();
    perform pg_advisory_xact_lock(20261111, 224);   -- planner_figures_status() sees a refresh under way by this lock
    begin
      v_gen := coalesce(st.generation, 0) + 1;
      v_default := exists (select 1 from public.worlds x where x.id = w and x.is_default);
      v_keys := '{}'; v_failed := '[]'::jsonb; n_all := 0; n_ok := 0;
      for f in
        select x.kind, x.key, x.airline_id, x.days
          from (-- each world: its figures; cabin_charges() and market_service_checks() take no world (the default world's)
                select k.kind, ''::text as key, null::bigint as airline_id, null::integer as days, 0::bigint as a_pos, k.n as k_pos
                  from unnest(array['airline_cards', 'growth_signals', 'hub_progress', 'route_loads', 'fleet_checks', 'cash_log',
                                    'shared_pairs_status']) with ordinality as k(kind, n)
                union all
                select k.kind, '', null, null, 0, 10 + k.n
                  from unnest(array['cabin_charges', 'market_service_checks']) with ordinality as k(kind, n)
                 where v_default
                union all
                -- each of our active airlines: its figures, then route and aircraft profit for 1, 3 and 7 days
                select k.kind, a.id::text, a.id, null, a.pos, 100 + k.n
                  from (select al.id, row_number() over (order by al.position nulls last, al.id) as pos
                          from public.airlines al join public.groups g on g.id = al.group_id and g.world_id = al.world_id
                         where al.world_id = w and al.active and g.kind = 'ours') a
                 cross join unnest(array['airline_profit', 'cash_forecast', 'fare_changes', 'fare_plan_status', 'fare_ladder',
                                         'fare_results', 'competition']) with ordinality as k(kind, n)
                union all
                select k.kind, a.id::text || ':' || d.d::text, a.id, d.d, a.pos, 200 + k.n * 10 + d.n
                  from (select al.id, row_number() over (order by al.position nulls last, al.id) as pos
                          from public.airlines al join public.groups g on g.id = al.group_id and g.world_id = al.world_id
                         where al.world_id = w and al.active and g.kind = 'ours') a
                 cross join unnest(array['route_profit', 'aircraft_profit']) with ordinality as k(kind, n)
                 cross join unnest(array[1, 3, 7]) with ordinality as d(d, n)) x
         order by x.a_pos, x.k_pos
      loop
        n_all := n_all + 1;
        v_keys := v_keys || (f.kind || '|' || f.key);
        begin
          t1 := clock_timestamp();
          if f.kind = p_fail then
            raise exception 'failed on purpose (p_fail, for the checks)';
          end if;
          -- each with the arguments the planner passes (spec §1, "What is stored")
          v_answer := case f.kind
            when 'airline_cards' then public.airline_cards(w, v_at)
            when 'growth_signals' then public.growth_signals(w, v_at)
            when 'hub_progress' then public.hub_progress(w, v_at)
            when 'route_loads' then public.route_loads(w, v_at)
            when 'fleet_checks' then public.fleet_checks(w, v_at)
            when 'cash_log' then public.cash_log(w, v_at)
            when 'shared_pairs_status' then public.shared_pairs_status(w, v_at)
            when 'cabin_charges' then public.cabin_charges(v_at)
            when 'market_service_checks' then public.market_service_checks(null::bigint, v_at)
            when 'airline_profit' then public.airline_profit(f.airline_id, v_at)
            when 'cash_forecast' then public.cash_forecast(f.airline_id, '[]'::jsonb, v_at)
            when 'fare_changes' then public.fare_changes(f.airline_id, v_at)
            when 'fare_plan_status' then public.fare_plan_status(f.airline_id, v_at)
            when 'fare_ladder' then public.fare_ladder(f.airline_id, v_at)
            when 'fare_results' then public.fare_results(f.airline_id, v_at)
            when 'competition' then public.competition(f.airline_id, v_at)
            when 'route_profit' then public.route_profit(f.airline_id, f.days, v_at)
            when 'aircraft_profit' then public.aircraft_profit(f.airline_id, f.days, v_at) end;
          if v_answer is null then
            raise exception '% gave no answer', f.kind;
          end if;
          insert into public.planner_figures as x (world_id, kind, key, answer, as_of, generation, worked_ms)
          values (w, f.kind, f.key, v_answer, v_at, v_gen, round(extract(epoch from clock_timestamp() - t1) * 1000)::int)
          on conflict (world_id, kind, key) do update
            set answer = excluded.answer, as_of = excluded.as_of, generation = excluded.generation, worked_ms = excluded.worked_ms;
          n_ok := n_ok + 1;
        exception when others then
          -- this figure keeps its previous answer; the rest go on
          v_failed := v_failed || jsonb_build_object('kind', f.kind, 'key', f.key, 'error', left(sqlerrm, 300));
        end;
      end loop;

      -- only the latest set is kept: an answer no longer in the list (an airline no longer active) goes
      delete from public.planner_figures x
       where x.world_id = w and x.kind <> 'route_story' and not ((x.kind || '|' || x.key) = any (v_keys));

      -- route pages worked out before this set are redone when a capture, scan or market run caused it (or it is the
      -- first); a save alone never redoes them
      v_routes_from := case when v_reason = 'planner saves' and st.sources ? 'routes_from' then st.sources ->> 'routes_from'
                            else private.fig_ts(v_at) end;
      select count(*), count(*) filter (where x.as_of >= v_routes_from::timestamptz) into n_total, n_done
        from public.routes ro
        left join public.planner_figures x on x.world_id = w and x.kind = 'route_story' and x.key = ro.id::text
       where ro.world_id = w and not ro.removed and exists (select 1 from public.rotations rt where rt.route_id = ro.id);

      v_err := case when jsonb_array_length(v_failed) > 0 then
                 left(format('%s of %s figures failed and kept their previous answer: %s', jsonb_array_length(v_failed), n_all,
                             (select string_agg((e ->> 'kind') || coalesce(' ' || nullif(e ->> 'key', ''), '') || ': ' || (e ->> 'error'), '; ' order by i)
                                from jsonb_array_elements(v_failed) with ordinality as x(e, i))), 2000) end;
      insert into public.planner_figures_state as s (world_id, generation, ready_at, sources, refreshing_since, routes_done, routes_total,
                                                     last_error, last_error_at)
      values (w, v_gen, clock_timestamp(), v_src || jsonb_build_object('as_of', private.fig_ts(v_at), 'routes_from', v_routes_from), t0,
              n_done, n_total, v_err, case when v_err is not null then clock_timestamp() end)
      on conflict (world_id) do update
        set generation = excluded.generation, ready_at = excluded.ready_at, sources = excluded.sources,
            refreshing_since = excluded.refreshing_since, routes_done = excluded.routes_done, routes_total = excluded.routes_total,
            last_error = excluded.last_error, last_error_at = excluded.last_error_at;

      v_note := format('generation %s (%s): %s of %s figures in %s s', v_gen, v_reason, n_ok, n_all,
                       round(extract(epoch from clock_timestamp() - t0)::numeric, 1))
                || case when v_err is not null then '; ' || v_err else '' end;
      perform private.job_run_add('figures', w, t0, case when v_err is null then 'ok' else 'failed' end, left(v_note, 2000),
                                  jsonb_build_object('reason', v_reason, 'as_of', private.fig_ts(v_at), 'generation', v_gen,
                                                     'figures', n_all, 'worked', n_ok, 'failed', v_failed,
                                                     'worked_ms', round(extract(epoch from clock_timestamp() - t0) * 1000)::int));
      v_out := v_out || jsonb_build_object('world_id', w, 'did', 'set', 'reason', v_reason, 'generation', v_gen, 'figures', n_all,
                                           'worked', n_ok, 'failed', v_failed,
                                           'worked_ms', round(extract(epoch from clock_timestamp() - t0) * 1000)::int);
    exception when others or query_canceled then
      -- the refresh failed as a whole: nothing of it is stored, the sources stay, and the next minute's run tries again
      v_err := left('the refresh failed: ' || sqlerrm, 2000);
      insert into public.planner_figures_state as s (world_id, last_error, last_error_at)
      values (w, v_err, clock_timestamp())
      on conflict (world_id) do update set last_error = excluded.last_error, last_error_at = excluded.last_error_at;
      perform private.job_run_add('figures', w, t0, 'failed', v_err,
                                  jsonb_build_object('reason', v_reason, 'as_of', private.fig_ts(v_at),
                                                     'worked_ms', round(extract(epoch from clock_timestamp() - t0) * 1000)::int));
      v_out := v_out || jsonb_build_object('world_id', w, 'did', 'failed', 'reason', v_reason, 'error', v_err);
    end;
    v_main := true;
  end loop;

  -- 4. the route pages, never in a run that stored a set: that set is visible as soon as this run ends
  if not v_main then
    foreach w in array v_rest loop
      v_out := v_out || (private.figures_routes(w, v_at) -> 'worlds');
    end loop;
  end if;
  return jsonb_build_object('as_of', private.fig_ts(v_at), 'worlds', v_out);
end
$function$;

create or replace function public.planner_figures_status(p_world bigint default null)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  w bigint; v_now timestamptz := now(); st public.planner_figures_state%rowtype; v_run jsonb; v_src jsonb;
  v_moved text[]; v_due boolean := false; v_reason text; v_wait timestamptz; v_pid integer; v_since timestamptz;
begin
  if not private.caller_is_staff() then raise exception 'only planner staff can read the stored figures'' status' using errcode = '42501'; end if;
  w := private.fig_world(p_world);
  select * into st from public.planner_figures_state s where s.world_id = w;
  -- light: a few indexed reads; no figure is worked out here
  v_run := private.figures_capture_running(w, v_now);
  v_src := private.figures_sources(w);
  if st.world_id is null or st.generation = 0 then
    v_due := true; v_reason := 'first set';
  else
    v_moved := array_remove(array[
      case when v_src -> 'capture_at' is distinct from st.sources -> 'capture_at' then 'capture' end,
      case when v_src -> 'scan_id' is distinct from st.sources -> 'scan_id' then 'world scan' end,
      case when v_src -> 'market_id' is distinct from st.sources -> 'market_id' then 'market pages' end], null);
    if cardinality(v_moved) > 0 then
      v_due := true; v_reason := 'new ' || array_to_string(v_moved, ', ');
    elsif v_src -> 'change_id' is distinct from st.sources -> 'change_id' then
      v_due := true; v_reason := 'planner saves';
      v_wait := (v_src ->> 'change_at')::timestamptz + interval '1 minute';
      if v_wait <= v_now then v_wait := null; end if;
    end if;
  end if;
  -- a refresh under way holds its lock until it ends (its writes can't be seen before then)
  select l.pid, a.xact_start into v_pid, v_since
    from pg_catalog.pg_locks l left join pg_catalog.pg_stat_activity a on a.pid = l.pid
   where l.locktype = 'advisory' and l.classid = 20261111 and l.objid = 224 and l.objsubid = 2 and l.granted
   limit 1;
  return jsonb_build_object(
    'world_id', w,
    'at', private.fig_ts(v_now),
    'generation', coalesce(st.generation, 0),
    'ready_at', private.fig_ts(st.ready_at),
    'set_as_of', st.sources -> 'as_of',
    'capture', v_run,
    'refresh', jsonb_build_object('due', v_due, 'reason', v_reason, 'waiting_until', private.fig_ts(v_wait),
                                  'running', v_pid is not null, 'running_since', private.fig_ts(v_since)),
    'routes', jsonb_build_object('done', coalesce(st.routes_done, 0), 'total', coalesce(st.routes_total, 0)),
    'last_error', st.last_error,
    'last_error_at', private.fig_ts(st.last_error_at),
    'landing_max_min', (select s.value from public.settings s where s.world_id = w and s.airline_id is null and s.key = 'figures_landing_max_min'));
end
$function$;

-- ============================================================ 5. the schedule
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
  -- the planner's figures stored after every capture (since 11 Nov, spec docs/specs/2026-11-11-stored-figures.md §1):
  -- every minute; most minutes it finds nothing to do
  perform cron.schedule('equinox-figures', '* * * * *', 'select private.figures_refresh()');
  return (select jsonb_agg(jsonb_build_object('job', j.jobname, 'schedule', j.schedule, 'command', j.command, 'active', j.active)
                           order by j.jobname)
            from cron.job j where j.jobname like 'equinox-%');
end
$function$;

-- ============================================================ 6. the Systems board: the stored figures' size
CREATE OR REPLACE FUNCTION public.system_status(p_world_id bigint DEFAULT NULL::bigint, p_as_of timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare w bigint; v_at timestamptz := coalesce(p_as_of, now()); v_month timestamptz; v_snap jsonb; v_job jsonb; v_fb timestamptz;
  v_backup jsonb; v_good jsonb; v_arch jsonb; v_clean jsonb; v_scan jsonb; v_stopped jsonb; v_market jsonb; v_un jsonb; v_db bigint; v_pdf bigint; v_site bigint;
  v_figs bigint;
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
  -- the stored figures (since 11 Nov, spec docs/specs/2026-11-11-stored-figures.md §1): the table with its indexes and TOAST,
  -- amber from 50 MB (the board marks amber at 70% of the trigger)
  v_figs := pg_total_relation_size('public.planner_figures'::regclass);

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
      jsonb_build_object('key', 'site_public', 'label', 'The website''s data', 'bytes', v_site, 'trigger_bytes', 500 * 1024::bigint),
      jsonb_build_object('key', 'planner_figures', 'label', 'Stored planner figures', 'bytes', v_figs,
                         'trigger_bytes', 50 * 1024 * 1024 * 10 / 7::bigint)));
end
$function$;

do $describe$
declare d text := obj_description('public.system_status(bigint, timestamptz)'::regprocedure, 'pg_proc');
begin
  if position('planner_figures' in coalesce(d, '')) = 0 then
    execute format('comment on function public.system_status(bigint, timestamptz) is %L', coalesce(d, '')
      || ' Since 11 Nov (spec docs/specs/2026-11-11-stored-figures.md §1) usage also lists planner_figures, the stored planner figures'' size with indexes and TOAST, amber from 50 MB (its trigger_bytes is 50 MB / 0.7, the board marking amber at 70%).');
  end if;
end
$describe$;

-- ============================================================ access
-- The internal functions: postgres only (the job runs as postgres). The status call: staff, read with GET.
revoke all on function private.figures_capture_running(bigint, timestamptz), private.figures_sources(bigint),
  private.figures_routes(bigint, timestamptz), private.figures_refresh(bigint, timestamptz, text)
  from public, anon, authenticated, service_role;
revoke all on function public.planner_figures_status(bigint) from public, anon, authenticated, service_role;
grant execute on function public.planner_figures_status(bigint) to authenticated;

-- ============================================================ descriptions
comment on function private.figures_capture_running(bigint, timestamp with time zone) is 'Whether a capture is running in a world at p_at (now by default), for the stored figures (since 11 Nov; spec docs/specs/2026-11-11-stored-figures.md §1): a capture page (game_capture_raw.captured_at) within settings.figures_capture_quiet_min minutes (5), a world scan of the world started within the hour that is neither done nor stopped (game_scans), or a market run started within the hour that is still open (market_runs). Answers running, what (capture, world scan or market pages: the latest stage), since (when the whole capture began: its pages'' first after a gap longer than the quiet window, or the scan''s or market run''s start), stage_since, last_page_at, and the progress: capture (airlines with a page this run of the active ones of ours, and the latest page''s airline and kind), scan (private.scan_progress()) and market (pages read, failed and expected). Light: a few indexed reads.';
comment on function private.figures_sources(bigint) is 'What a stored set of the planner''s figures depends on in a world (since 11 Nov; spec docs/specs/2026-11-11-stored-figures.md §1): capture_at, the latest capture page''s time (game_capture_raw); scan_id, the latest finished world scan; market_id, the latest finished market run; change_id and change_at, the latest change_log row of the world (or of no world: countries and airports), which every write to the planner tables makes. private.figures_refresh() works a new set out when the first three move, or when only the last does and it is more than a minute old. Light: indexed reads.';
comment on function private.figures_refresh(bigint, timestamp with time zone, text) is 'Stores the planner''s figures (pg_cron equinox-figures, every minute, as postgres; since 11 Nov, to-do 223, spec docs/specs/2026-11-11-stored-figures.md §1), in each world with active airlines of ours (or p_world), at p_at (now by default). One run at a time (an advisory lock; a run that finds another under way skips). While a capture is running (private.figures_capture_running()), nothing. When there is no set yet, or the capture, scan or market stamps moved (private.figures_sources()), or only the planner tables did and the last save is more than a minute old: every figure of planner_figures'' list at the one moment, each with the planner''s arguments and on its own (one that fails keeps its previous answer and the rest go on), answers no longer in the list removed, then generation, ready_at and sources moved on together, all in the job''s one transaction, so the planner never sees half a set; one job_runs row (figures: the reason, the time taken, the figures that failed; ok, or failed when any did). A refresh that fails as a whole stores nothing and notes last_error. Otherwise the route pages (private.figures_routes()), never in the run that stored a set. Its own statement limit is 5 minutes. p_fail: a figure kind made to fail on purpose, for the checks only (database/tests/stored_figures_test.sql). postgres only.';
comment on function private.figures_routes(bigint, timestamp with time zone) is 'The route pages of the stored figures (since 11 Nov; spec docs/specs/2026-11-11-stored-figures.md §1), run by private.figures_refresh() in a minute when no new set is due: in each world with active airlines of ours (or p_world), unless a capture is running or a new set is due first, the flown routes'' route_story() (rotations, not removed) whose stored page is older than the set''s routes_from (the latest set a capture, scan or market run caused) or missing, oldest first, at p_at (now by default), for up to settings.figures_route_budget_s seconds (40), each on its own (one that fails keeps its previous page and notes last_error); the pages of routes no longer flown go; routes_done and routes_total noted. A save alone never redoes them. The same one-run-at-a-time lock as the refresh. postgres only.';
comment on function public.planner_figures_status(bigint) is 'Where the planner''s stored figures stand in a world (the default when null), for the planner''s landing page (since 11 Nov; spec docs/specs/2026-11-11-stored-figures.md §1): generation and ready_at (the set to load) and set_as_of (its moment); capture, whether a capture is running, what, since when and its progress (private.figures_capture_running()); refresh, whether a new set is due (and why: first set, new capture, world scan or market pages, or planner saves, with waiting_until while the last save is under a minute old) and whether one is under way (from the running job''s lock) and since when; routes, the route pages done of the flown routes; last_error and last_error_at; landing_max_min (settings.figures_landing_max_min). Light: it never works a figure out. Staff only (signed in), read with GET; runs as owner with an empty search path.';
comment on function private.schedule_jobs() is 'Schedules the database jobs with pg_cron, by name, so it can run again safely: equinox-snapshot-fallback at 10:00 UTC (private.job_snapshot_fallback), equinox-cleanup at 10:20 UTC (private.job_cleanup), since 10 Nov equinox-capture-dispatch at 09:30 and 21:30 UTC (private.capture_dispatch) and equinox-capture-dispatch-answer at 09:40 and 21:40 UTC (private.capture_dispatch_answer), and since 11 Nov equinox-figures every minute (private.figures_refresh, the stored planner figures). Run by migrations 20261011150000_jobs, 20261110040000_unattended_capture and 20261111020000_stored_figures, and again after a full restore (the backup copies no schedules). Answers with the jobs as the scheduler has them.';

select private.schedule_jobs();

select set_config('equinox.actor', '', true), set_config('equinox.actor_detail', '', true);

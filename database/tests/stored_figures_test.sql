-- The planner's figures stored after every capture, part 1: the database (to-do 223; spec
-- docs/specs/2026-11-11-stored-figures.md §1 and §3; migration 20261111020000_stored_figures.sql). Run by
-- database/rehearse.sh on the copy of last night's backup, after the new migrations, inside a transaction that is rolled
-- back. A failed check stops with an error that says which (kinds, keys, ids and counts, never figures).
--   1. The catalogue: planner_figures and planner_figures_state described (every column), RLS on with one staff read rule,
--      staff read only, nothing for anon; the three settings in every world, described; the four internal functions
--      postgres only, as the caller, with an empty search path; planner_figures_status() signed in only, stable, as owner
--      with an empty search path; every one described; job_runs takes figures; private.schedule_jobs() lists
--      equinox-figures every minute.
--   2. A set at the copy's latest capture plus one hour (moved past a world scan or market run the copy left open, if
--      any): generation 1, every figure of the list (each world-wide one, cabin_charges and market_service_checks in the
--      default world, each of our active airlines' seven and its route and aircraft profit for 1, 3 and 7 days) stored at
--      that moment, none failed, and every stored answer equal to the live function called as the planner calls it with
--      the same as_of; the state's sources are figures_sources()' with the set's moment; one job_runs row (figures, ok).
--   3. Route pages: the next minute's run stores no new set but route pages (a 3-second budget for the test), each equal
--      to route_story() at its as_of; routes_done and routes_total counted.
--   4. A failed figure: a capture page arrives (kind html, a page inspection); a run ten minutes on with fare_results made
--      to fail (p_fail) stores generation 2: every fare_results keeps its generation-1 answer, every other figure moved
--      on, last_error names fare_results, the job's row is failed; the route pages are due again (routes_done 0).
--   5. A capture running: a page inside the quiet window makes figures_capture_running() say so and the run do nothing
--      (generation still 2, no new job row).
--   6. planner_figures_status(): as staff, light (each call under 100 ms) with its parts; staff read the stored rows, can't
--      write them; an account that isn't staff reads none and is refused the status; signed out is refused both.

create temporary table t_sf (k text primary key, v jsonb) on commit drop;
create temporary table t_sf_gen1 (kind text, key text, answer jsonb, primary key (kind, key)) on commit drop;
grant select on t_sf to authenticated, anon;
insert into public.planner_users (email) values ('stored-figures-staff@example.com') on conflict do nothing;

-- ---------------------------------------------------------------- 1. the catalogue
do $test$
declare bad text; f text; n_worlds int := (select count(*) from public.worlds); r jsonb;
  fns text[] := array['private.figures_capture_running(bigint, timestamptz)', 'private.figures_sources(bigint)',
                      'private.figures_routes(bigint, timestamptz)', 'private.figures_refresh(bigint, timestamptz, text)'];
begin
  -- the tables: described, every column too; RLS on with exactly one staff read rule; staff read only, anon nothing
  select string_agg(c.relname, ', ') into bad from pg_class c
   where c.oid in ('public.planner_figures'::regclass, 'public.planner_figures_state'::regclass)
     and (length(coalesce(obj_description(c.oid, 'pg_class'), '')) < 200 or not c.relrowsecurity
          or exists (select 1 from pg_attribute a where a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped
                        and length(coalesce(col_description(c.oid, a.attnum), '')) < 10));
  assert bad is null, 'not described (or a column isn''t), or RLS is off: ' || bad;
  select string_agg(t.name || ' (' || coalesce(p.rules, 'none') || ')', ', ') into bad
    from unnest(array['planner_figures', 'planner_figures_state']) t(name) left join lateral (
      select string_agg(lower(cmd) || ' ' || array_to_string(roles, '+') || ' ' || coalesce(qual, ''), '; ') as rules
        from pg_policies where schemaname = 'public' and tablename = t.name) p on true
   where p.rules is distinct from 'select authenticated ( SELECT is_planner_user() AS is_planner_user)';
  assert bad is null, 'not exactly one staff read rule on: ' || bad;
  select string_agg(t.name || ' ' || x.priv || ' for ' || x.who, ', ') into bad
    from unnest(array['public.planner_figures', 'public.planner_figures_state']) t(name)
   cross join (values ('anon', 'select'), ('anon', 'insert'), ('anon', 'update'), ('anon', 'delete'), ('authenticated', 'insert'),
                      ('authenticated', 'update'), ('authenticated', 'delete'), ('authenticated', 'truncate')) x(who, priv)
   where has_table_privilege(x.who, t.name, x.priv);
  assert bad is null, 'more than staff read: ' || bad;
  assert has_table_privilege('authenticated', 'public.planner_figures', 'select') and has_table_privilege('authenticated', 'public.planner_figures_state', 'select'),
    'staff can''t read the stored figures';

  -- the settings: every world, described, with since and reason
  select string_agg(x.k || ' in ' || w.name, ', ') into bad
    from public.worlds w
   cross join (values ('figures_capture_quiet_min', '5'), ('figures_route_budget_s', '40'), ('figures_landing_max_min', '30')) x(k, v)
   where not exists (select 1 from public.settings s where s.world_id = w.id and s.airline_id is null and s.key = x.k
                        and s.value = x.v::jsonb and length(coalesce(s.description, '')) > 100 and s.unit is not null
                        and s.since is not null and coalesce(s.reason, '') <> '');
  assert bad is null, 'settings missing, not as the spec says or undescribed: ' || bad;

  -- the functions
  foreach f in array fns loop
    assert not has_function_privilege('anon', f, 'execute') and not has_function_privilege('authenticated', f, 'execute')
       and not has_function_privilege('service_role', f, 'execute'), f || ' can be called from outside the database';
    assert (select not p.prosecdef and coalesce('search_path=""' = any (p.proconfig), false) from pg_proc p where p.oid = f::regprocedure),
      f || ' runs as owner or has no empty search path';
    assert length(coalesce(obj_description(f::regprocedure, 'pg_proc'), '')) > 300, f || ' has no description';
  end loop;
  assert (select p.proconfig @> array['statement_timeout=5min'] from pg_proc p where p.oid = 'private.figures_refresh(bigint, timestamptz, text)'::regprocedure),
    'private.figures_refresh() hasn''t its own 5-minute limit';
  f := 'public.planner_figures_status(bigint)';
  assert (select p.prosecdef and p.provolatile = 's' and coalesce('search_path=""' = any (p.proconfig), false) and p.proconfig is not null
                 and not exists (select 1 from unnest(p.proconfig) c where c like 'statement_timeout=%')
            from pg_proc p where p.oid = f::regprocedure),
    f || ' isn''t stable, run as owner with an empty search path (and no limit of its own)';
  assert not has_function_privilege('anon', f, 'execute') and has_function_privilege('authenticated', f, 'execute'),
    f || ' isn''t signed in only';
  assert not exists (select 1 from pg_proc p cross join aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                      where p.oid = f::regprocedure and a.grantee = 0), f || ' is open to public';
  assert length(coalesce(obj_description(f::regprocedure, 'pg_proc'), '')) > 300, f || ' has no description';

  -- job_runs takes figures, and still refuses a job it doesn't know
  perform private.job_run_add('figures', null, now() - interval '400 days', 'ok', 'catalogue check', null);
  begin
    perform private.job_run_add('figures_nothing', null, now() - interval '400 days', 'ok', 'catalogue check', null);
    raise exception 'job_runs took a job it doesn''t know';
  exception when check_violation then null;
  end;
  -- the schedule
  r := private.schedule_jobs();
  assert r @> '[{"job": "equinox-figures", "schedule": "* * * * *", "command": "select private.figures_refresh()"}]'::jsonb,
    'private.schedule_jobs() doesn''t list equinox-figures every minute: ' || r::text;
  raise notice 'catalogue: the two tables described, RLS with one staff read rule, staff read only, anon nothing; the three settings in each of the % world(s); four internal functions postgres only, planner_figures_status() signed in only and stable; job_runs takes figures; equinox-figures every minute',
    n_worlds;
end
$test$;

-- ---------------------------------------------------------------- 2. a set at the copy's latest capture plus one hour
do $test$
declare
  w bigint := (select id from public.worlds where is_default); v_last timestamptz; v_at timestamptz; v_run jsonb; v_moved text;
  d jsonb; st public.planner_figures_state%rowtype; n_air int; n_exp int; n_got int; bad text; fr record; v_live jsonb;
  n_same int := 0; t0 timestamptz; v_ms int; j record;
begin
  -- one run at a time: wait for any run of the job on the copy (rehearse.sh pauses it), then start from nothing
  perform pg_advisory_xact_lock(20261111, 223);
  delete from public.planner_figures x where x.world_id = w;
  delete from public.planner_figures_state x where x.world_id = w;
  -- route pages get a 3-second budget for the test (section 3); changed now, so the set below already counts the save
  update public.settings s set value = '3'::jsonb where s.world_id = w and s.airline_id is null and s.key = 'figures_route_budget_s';

  select max(r.captured_at) into v_last from public.game_capture_raw r where r.world_id = w;
  assert v_last is not null, 'the copy has no capture page';
  v_at := v_last + interval '1 hour';
  -- a world scan or market run the copy left open within the hour counts as a capture running: past it
  v_run := private.figures_capture_running(w, v_at);
  if (v_run ->> 'running')::boolean then
    v_moved := v_run ->> 'what';
    v_at := (v_run ->> 'stage_since')::timestamptz + interval '1 hour 1 minute';
    v_run := private.figures_capture_running(w, v_at);
  end if;
  assert not (v_run ->> 'running')::boolean, 'a capture is still running at ' || v_at || ': ' || v_run::text;
  insert into t_sf values ('w', to_jsonb(w)), ('at', to_jsonb(v_at));

  t0 := clock_timestamp();
  d := private.figures_refresh(w, v_at);
  v_ms := round(extract(epoch from clock_timestamp() - t0) * 1000);
  assert d #>> '{worlds,0,did}' = 'set' and d #>> '{worlds,0,reason}' = 'first set' and (d #>> '{worlds,0,generation}')::int = 1,
    'the first run didn''t store a first set: ' || left(d::text, 400);
  assert jsonb_array_length(d #> '{worlds,0,failed}') = 0, 'figures failed on the copy: ' || left((d #> '{worlds,0,failed}')::text, 600);

  -- every figure of the list, at the one moment, in generation 1
  select count(*) into n_air from public.airlines a join public.groups g on g.id = a.group_id and g.world_id = a.world_id
   where a.world_id = w and a.active and g.kind = 'ours';
  n_exp := 7 + 2 + n_air * (7 + 6);
  select count(*) into n_got from public.planner_figures x where x.world_id = w and x.kind <> 'route_story';
  assert n_got = n_exp, format('%s figures stored, %s expected (%s airlines)', n_got, n_exp, n_air);
  select string_agg(x.kind || ' ' || x.key, ', ') into bad from public.planner_figures x
   where x.world_id = w and (x.as_of <> v_at or x.generation <> 1 or x.kind = 'route_story');
  assert bad is null, 'not at the set''s moment or not generation 1: ' || bad;
  select string_agg(e.kind || ' ' || e.key, ', ') into bad
    from (select k.kind, '' as key from unnest(array['airline_cards', 'growth_signals', 'hub_progress', 'route_loads', 'fleet_checks',
                                                       'cash_log', 'shared_pairs_status', 'cabin_charges', 'market_service_checks']) k(kind)
          union all
          select k.kind, a.id::text from public.airlines a join public.groups g on g.id = a.group_id and g.world_id = a.world_id
           cross join unnest(array['airline_profit', 'cash_forecast', 'fare_changes', 'fare_plan_status', 'fare_ladder', 'fare_results',
                                   'competition']) k(kind)
           where a.world_id = w and a.active and g.kind = 'ours'
          union all
          select k.kind, a.id || ':' || dd.days from public.airlines a join public.groups g on g.id = a.group_id and g.world_id = a.world_id
           cross join unnest(array['route_profit', 'aircraft_profit']) k(kind) cross join unnest(array[1, 3, 7]) dd(days)
           where a.world_id = w and a.active and g.kind = 'ours') e
   where not exists (select 1 from public.planner_figures x where x.world_id = w and x.kind = e.kind and x.key = e.key);
  assert bad is null, 'not stored: ' || bad;

  -- every stored answer equals the live function, called as the planner calls it, at the same as_of
  for fr in select x.kind, x.key, x.answer, x.as_of, nullif(split_part(x.key, ':', 1), '')::bigint as airline_id,
                  nullif(split_part(x.key, ':', 2), '')::int as days
             from public.planner_figures x where x.world_id = w and x.kind <> 'route_story' order by x.kind, x.key loop
    v_live := case fr.kind
      when 'airline_cards' then public.airline_cards(p_world_id => w, p_as_of => fr.as_of)
      when 'growth_signals' then public.growth_signals(p_world_id => w, p_as_of => fr.as_of)
      when 'hub_progress' then public.hub_progress(p_world_id => w, p_as_of => fr.as_of)
      when 'route_loads' then public.route_loads(p_world_id => w, p_as_of => fr.as_of)
      when 'fleet_checks' then public.fleet_checks(p_world_id => w, p_as_of => fr.as_of)
      when 'cash_log' then public.cash_log(p_world_id => w, p_as_of => fr.as_of)
      when 'shared_pairs_status' then public.shared_pairs_status(p_world_id => w, p_as_of => fr.as_of)
      when 'cabin_charges' then public.cabin_charges(p_as_of => fr.as_of)
      when 'market_service_checks' then public.market_service_checks(p_as_of => fr.as_of)
      when 'airline_profit' then public.airline_profit(p_airline_id => fr.airline_id, p_as_of => fr.as_of)
      when 'cash_forecast' then public.cash_forecast(p_airline_id => fr.airline_id, p_as_of => fr.as_of)
      when 'fare_changes' then public.fare_changes(p_airline_id => fr.airline_id, p_as_of => fr.as_of)
      when 'fare_plan_status' then public.fare_plan_status(p_airline_id => fr.airline_id, p_as_of => fr.as_of)
      when 'fare_ladder' then public.fare_ladder(p_airline_id => fr.airline_id, p_as_of => fr.as_of)
      when 'fare_results' then public.fare_results(p_airline_id => fr.airline_id, p_as_of => fr.as_of)
      when 'competition' then public.competition(p_airline_id => fr.airline_id, p_as_of => fr.as_of)
      when 'route_profit' then public.route_profit(p_airline_id => fr.airline_id, p_days => fr.days, p_as_of => fr.as_of)
      when 'aircraft_profit' then public.aircraft_profit(p_airline_id => fr.airline_id, p_days => fr.days, p_as_of => fr.as_of) end;
    assert v_live is not null, 'no live answer for ' || fr.kind || ' ' || fr.key;
    assert v_live = fr.answer, 'the stored answer differs from the live one: ' || fr.kind || ' ' || fr.key;
    n_same := n_same + 1;
    insert into t_sf_gen1 values (fr.kind, fr.key, fr.answer);
  end loop;

  -- the state: generation 1, its sources and moment; the job's row
  select * into st from public.planner_figures_state s where s.world_id = w;
  assert st.generation = 1 and st.ready_at is not null and st.refreshing_since <= st.ready_at and st.last_error is null,
    'the state isn''t generation 1 with no error';
  assert st.sources = private.figures_sources(w) || jsonb_build_object('as_of', private.fig_ts(v_at), 'routes_from', private.fig_ts(v_at)),
    'the state''s sources aren''t figures_sources() with the set''s moment: ' || st.sources::text;
  select x.* into j from public.job_runs x where x.job = 'figures' and x.world_id = w order by x.id desc limit 1;
  assert j.status = 'ok' and j.details ->> 'reason' = 'first set' and (j.details ->> 'generation')::int = 1
     and (j.details ->> 'figures')::int = n_exp and j.finished_at >= j.started_at,
    'no job_runs row (figures, ok, first set) for the set: ' || coalesce(j.note, 'none');
  raise notice 'a set at the copy''s latest capture plus one hour%: % figures for % airlines in % s, none failed, generation 1; every stored answer (%) equals the live function at the same as_of; the state''s sources and the job''s row (figures, ok)',
    coalesce(' (moved past the ' || v_moved || ' the copy left open)', ''), n_exp, n_air, round(v_ms / 1000.0, 1), n_same;
end
$test$;

-- ---------------------------------------------------------------- 3. route pages, the next minute
do $test$
declare w bigint := (select (v #>> '{}')::bigint from t_sf where k = 'w'); v_at timestamptz := (select (v #>> '{}')::timestamptz from t_sf where k = 'at');
  d jsonb; st public.planner_figures_state%rowtype; n_flown int; n_pages int; r record; bad text;
begin
  d := private.figures_refresh(w, v_at + interval '1 minute');
  assert not exists (select 1 from jsonb_array_elements(d -> 'worlds') e where e ->> 'did' = 'set'), 'a second set was stored with nothing new: ' || left(d::text, 300);
  select e into d from jsonb_array_elements(d -> 'worlds') e where e ->> 'did' = 'route pages';
  assert d is not null, 'the next minute''s run did no route pages';
  select count(*) into n_flown from public.routes ro
   where ro.world_id = w and not ro.removed and exists (select 1 from public.rotations rt where rt.route_id = ro.id);
  select count(*) into n_pages from public.planner_figures x where x.world_id = w and x.kind = 'route_story';
  assert n_pages >= least(n_flown, 1) and n_pages = (d ->> 'worked')::int, format('%s route pages stored, %s worked', n_pages, d ->> 'worked');
  select * into st from public.planner_figures_state s where s.world_id = w;
  assert st.generation = 1 and st.routes_total = n_flown and st.routes_done = n_pages,
    format('the state says %s of %s route pages (generation %s); %s stored of %s flown', st.routes_done, st.routes_total, st.generation, n_pages, n_flown);
  for r in select x.key, x.answer, x.as_of, x.generation from public.planner_figures x where x.world_id = w and x.kind = 'route_story' loop
    assert r.generation = 1 and r.as_of = v_at + interval '1 minute', 'route page ' || r.key || ' isn''t generation 1 at the run''s moment';
    assert r.answer = public.route_story(p_route_id => r.key::bigint, p_as_of => r.as_of), 'the stored route page differs from the live one: route ' || r.key;
  end loop;
  insert into t_sf values ('pages', to_jsonb(n_pages));
  raise notice 'route pages: the next minute''s run stored no set but % route page(s) of % flown in a 3-second budget, each equal to route_story() at its as_of', n_pages, n_flown;
end
$test$;

-- ---------------------------------------------------------------- 4. a failed figure keeps its answer; the generation moves on
do $test$
declare w bigint := (select (v #>> '{}')::bigint from t_sf where k = 'w'); v_at timestamptz := (select (v #>> '{}')::timestamptz from t_sf where k = 'at');
  a record; d jsonb; st public.planner_figures_state%rowtype; bad text; n_fail int; n_air int; j record;
begin
  select al.id, coalesce(al.planner_name, al.game_name) as name into a
    from public.airlines al join public.groups g on g.id = al.group_id and g.world_id = al.world_id
   where al.world_id = w and al.active and g.kind = 'ours' order by al.id limit 1;
  -- a later capture page (a page inspection: nothing reads it as a capture's page)
  insert into public.game_capture_raw (world_id, airline_id, airline, kind, rows, captured_at)
  values (w, a.id, a.name, 'html', '[]', v_at + interval '2 minutes');
  d := private.figures_refresh(w, v_at + interval '10 minutes', 'fare_results');
  select count(*) into n_air from public.airlines al join public.groups g on g.id = al.group_id and g.world_id = al.world_id
   where al.world_id = w and al.active and g.kind = 'ours';
  assert d #>> '{worlds,0,did}' = 'set' and d #>> '{worlds,0,reason}' = 'new capture' and (d #>> '{worlds,0,generation}')::int = 2,
    'the run after a new capture page didn''t store generation 2: ' || left(d::text, 300);
  select count(*) into n_fail from jsonb_array_elements(d #> '{worlds,0,failed}') e where e ->> 'kind' = 'fare_results';
  assert n_fail = n_air and jsonb_array_length(d #> '{worlds,0,failed}') = n_air,
    format('%s failures, %s expected (fare_results for each airline): %s', jsonb_array_length(d #> '{worlds,0,failed}'), n_air, left((d #> '{worlds,0,failed}')::text, 300));
  -- each fare_results keeps its generation-1 answer and moment; every other figure moved on
  select string_agg(x.kind || ' ' || x.key, ', ') into bad
    from public.planner_figures x join t_sf_gen1 g on g.kind = x.kind and g.key = x.key
   where x.world_id = w and x.kind = 'fare_results' and (x.generation <> 1 or x.as_of <> v_at or x.answer is distinct from g.answer);
  assert bad is null, 'a failed figure didn''t keep its previous answer: ' || bad;
  select string_agg(x.kind || ' ' || x.key, ', ') into bad from public.planner_figures x
   where x.world_id = w and x.kind not in ('fare_results', 'route_story') and (x.generation <> 2 or x.as_of <> v_at + interval '10 minutes');
  assert bad is null, 'figures that didn''t move on to generation 2: ' || bad;
  select * into st from public.planner_figures_state s where s.world_id = w;
  assert st.generation = 2 and st.last_error like '% figures failed and kept their previous answer: fare_results%' and st.last_error_at is not null,
    'the state isn''t generation 2 with last_error naming fare_results: ' || coalesce(st.last_error, 'none');
  assert st.sources ->> 'capture_at' = private.fig_ts(v_at + interval '2 minutes') and st.routes_done = 0
     and st.sources ->> 'routes_from' = private.fig_ts(v_at + interval '10 minutes'),
    'the new capture page didn''t move the sources, or the route pages aren''t due again';
  select x.* into j from public.job_runs x where x.job = 'figures' and x.world_id = w order by x.id desc limit 1;
  assert j.status = 'failed' and (j.details ->> 'generation')::int = 2 and j.note like '%fare_results%', 'the job''s row isn''t failed, naming fare_results';
  raise notice 'a failed figure: after a new capture page, fare_results made to fail for each of % airlines kept its generation-1 answer while every other figure moved on to generation 2; last_error and the job''s row (failed) name it; the route pages are due again',
    n_air;
end
$test$;

-- ---------------------------------------------------------------- 5. a capture running: nothing
do $test$
declare w bigint := (select (v #>> '{}')::bigint from t_sf where k = 'w'); v_at timestamptz := (select (v #>> '{}')::timestamptz from t_sf where k = 'at');
  a record; v_run jsonb; d jsonb; n_jobs int;
begin
  select al.id, coalesce(al.planner_name, al.game_name) as name into a
    from public.airlines al join public.groups g on g.id = al.group_id and g.world_id = al.world_id
   where al.world_id = w and al.active and g.kind = 'ours' order by al.id limit 1;
  insert into public.game_capture_raw (world_id, airline_id, airline, kind, rows, captured_at)
  values (w, a.id, a.name, 'html', '[]', v_at + interval '20 minutes');
  v_run := private.figures_capture_running(w, v_at + interval '22 minutes');
  assert (v_run ->> 'running')::boolean and v_run ->> 'what' = 'capture' and v_run ->> 'since' = private.fig_ts(v_at + interval '20 minutes')
     and (v_run #>> '{capture,airlines_done}')::int = 1,
    'a page two minutes ago isn''t a capture running since it came: ' || v_run::text;
  select count(*) into n_jobs from public.job_runs x where x.job = 'figures';
  d := private.figures_refresh(w, v_at + interval '22 minutes');
  assert d #>> '{worlds,0,did}' = 'nothing' and d #>> '{worlds,0,why}' like 'a capture is running%', 'the run didn''t wait for the capture: ' || left(d::text, 300);
  assert (select s.generation from public.planner_figures_state s where s.world_id = w) = 2, 'the generation moved during a capture';
  assert (select count(*) from public.job_runs x where x.job = 'figures') = n_jobs, 'a run during a capture wrote a job row';
  -- the quiet window passed: no longer running
  assert not (private.figures_capture_running(w, v_at + interval '26 minutes') ->> 'running')::boolean,
    'six minutes after the last page a capture is still running';
  insert into t_sf values ('rows', to_jsonb((select count(*) from public.planner_figures x where x.world_id = w)));
  raise notice 'a capture running: a page two minutes before makes figures_capture_running() say capture since that page, and the run does nothing (generation still 2, no job row); six minutes on it has ended';
end
$test$;

-- ---------------------------------------------------------------- 6. the status call, and who may read what
do $$ begin perform set_config('request.jwt.claims',
  '{"sub": "00000000-0000-4000-8000-0000000000f1", "email": "stored-figures-staff@example.com", "role": "authenticated"}', true); end $$;
set local role authenticated;
do $test$
declare w bigint := (select (v #>> '{}')::bigint from t_sf where k = 'w'); d jsonb; t0 timestamptz; v_ms numeric; v_max numeric := 0; n int;
begin
  d := public.planner_figures_status(w);   -- once to warm up
  for i in 1 .. 3 loop
    t0 := clock_timestamp();
    d := public.planner_figures_status(w);
    v_ms := extract(epoch from clock_timestamp() - t0) * 1000;
    v_max := greatest(v_max, v_ms);
  end loop;
  assert v_max < 100, format('planner_figures_status() took %s ms (at most 100)', round(v_max, 1));
  assert d ?& array['generation', 'ready_at', 'set_as_of', 'capture', 'refresh', 'routes', 'last_error', 'last_error_at', 'landing_max_min']
     and (d ->> 'generation')::int = 2 and d -> 'capture' ? 'running' and d -> 'refresh' ?& array['due', 'reason', 'running']
     and d -> 'routes' ?& array['done', 'total'] and d -> 'landing_max_min' = '30'::jsonb and d ->> 'last_error' like '%fare_results%',
    'planner_figures_status() lacks a part: ' || left(d::text, 400);
  -- staff read the stored rows, and can't write them
  select count(*) into n from public.planner_figures x where x.world_id = w;
  assert n > 0 and n = (select (v #>> '{}')::int from t_sf where k = 'rows'), format('staff read %s stored figures, postgres %s', n, (select v from t_sf where k = 'rows'));
  assert (select count(*) from public.planner_figures_state s where s.world_id = w) = 1, 'staff can''t read the state';
  begin
    delete from public.planner_figures x where x.world_id = w;
    raise exception 'staff could delete stored figures';
  exception when insufficient_privilege then null;
  end;
  begin
    update public.planner_figures_state s set generation = 99 where s.world_id = w;
    raise exception 'staff could change the state';
  exception when insufficient_privilege then null;
  end;
  raise notice 'planner_figures_status() as staff: every part, generation 2, each call under 100 ms (the slowest %); staff read the stored rows and the state and can''t write them',
    round(v_max, 1) || ' ms';
end
$test$;
reset role;

do $$ begin perform set_config('request.jwt.claims',
  '{"sub": "00000000-0000-4000-8000-0000000000f2", "email": "stored-figures-other@example.com", "role": "authenticated"}', true); end $$;
set local role authenticated;
do $test$
declare n int := 0;
begin
  assert (select count(*) from public.planner_figures) = 0 and (select count(*) from public.planner_figures_state) = 0,
    'an account that isn''t staff reads the stored figures';
  begin perform public.planner_figures_status(null); exception when insufficient_privilege then n := n + 1; end;
  assert n = 1, 'an account that isn''t staff wasn''t refused planner_figures_status()';
end
$test$;
reset role;

set local role anon;
do $test$
declare n int := 0;
begin
  begin perform public.planner_figures_status(null); exception when insufficient_privilege then n := n + 1; end;
  begin perform count(*) from public.planner_figures; exception when insufficient_privilege then n := n + 1; end;
  begin perform count(*) from public.planner_figures_state; exception when insufficient_privilege then n := n + 1; end;
  assert n = 3, 'signed out, the status or the stored figures weren''t refused';
end
$test$;
reset role;

do $$ begin raise notice 'who: an account that isn''t staff reads no stored figure and is refused the status; signed out is refused the status and both tables'; end $$;
do $$ begin raise notice 'stored figures: all checks passed'; end $$;

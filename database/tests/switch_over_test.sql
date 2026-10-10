-- The switch-over (#13 build, pull request 9; design §8 "At the switch-over", §9 "Rollback"). Run by
-- database/rehearse.sh on the copy of last night's backup, after the new migrations, inside a transaction that is rolled
-- back. A failed check stops with an error that says where (ids, dates and counts, never values).
--   1. The freeze: planner_state and planner_loads refuse an insert, update, delete or truncate, from postgres too, with
--      "frozen since <date>; write to the tables"; signed in, staff can't write them either. The side by side is off: a
--      save through the adapter changes neither old row and writes no job_runs row.
--   2. save_loads() writes only the tables: a whole day typed replaces that day's flights, a paste sets and clears single
--      flights, a new month works, logged as planner (save_loads); its answer is the month as planner_loads_get() gives
--      it; planner_loads doesn't change. The capture's loads step leaves planner_loads alone, and the getter shows the
--      captured flight.
--   3. A loads day's done, one rule: part-way through an evening's capture the day isn't done, in the getter or in the
--      capture's loads step (run with the freeze lifted, as after a rollback); once the last airline is in, it is in
--      both, and a day typed done is done.
--   4. A save's base covers its whole millisecond: a tab that loaded right after Claude changed a to-do can then change
--      that to-do itself; a change after its base is still skipped.
--   5. Rollback: after saves through the adapter, private.unfreeze_planner_state() makes planner_state and planner_loads
--      equal the getters exactly, lifts the freeze, gives staff back planner_state's writes and puts the side by side
--      back; a save of the old row as the old planner makes it is then copied into the tables and its comparison is ok;
--      private.freeze_planner_state() freezes again.
--   6. Who may call the new functions.
-- The side by side's triggers run when a transaction commits; this test runs them as a commit would
-- (pg_temp.commit_triggers), as adapter_side_by_side_test.sql does.

create function pg_temp.doc() returns jsonb language sql as $$ select (public.planner_state_get() ->> 'json')::jsonb $$;
create function pg_temp.month(p text) returns jsonb language sql as $$ select g.json::jsonb from public.planner_loads_get() g where g.month = p $$;
create function pg_temp.ms() returns bigint language sql as $$ select floor(extract(epoch from clock_timestamp()) * 1000)::bigint $$;
create function pg_temp.commit_triggers() returns void language plpgsql as $$
begin
  execute 'set constraints all immediate';
  execute 'set constraints all deferred';
end
$$;
create function pg_temp.with_todo(p_doc jsonb, p_id text, p_set jsonb) returns jsonb language sql as $$
  select jsonb_set(p_doc, '{todos}', (select jsonb_agg(case when e ->> 'id' = p_id then e || p_set else e end order by o)
                                         from jsonb_array_elements(p_doc -> 'todos') with ordinality as x(e, o)))
$$;
create function pg_temp.old_rows() returns text language sql as $$
  select md5((select json || saved_at from public.planner_state where id = 'main')
             || coalesce((select string_agg(month || json || saved_at, '|' order by month) from public.planner_loads), ''))
$$;
-- whether the old rows were frozen during this rehearsal (database/tests/before/switch_over_before.sql); null outside one
create function pg_temp.switched_tonight() returns boolean language plpgsql as $$
declare v boolean;
begin
  if to_regclass('rehearsal_before.planner_frozen') is null then return null; end if;
  execute 'select not frozen from rehearsal_before.planner_frozen' into v;
  return v;
end
$$;
create temporary table t_said (part int primary key, line text) on commit drop;
create temporary table t_mark (k text primary key, v text) on commit drop;
insert into public.planner_users (email) values ('switch-over-staff@example.com') on conflict do nothing;

-- ---------------------------------------------------------------- 1. the freeze, and the side by side off
do $test$
declare v_since text := private.planner_frozen_since('public.planner_state'::regclass); t text; v_sql text; refused boolean;
  v_msg text; v_old text := pg_temp.old_rows(); v_job bigint := coalesce((select max(id) from public.job_runs), 0); r jsonb;
  switched boolean := coalesce(pg_temp.switched_tonight(), false);
begin
  assert v_since is not null and private.planner_frozen_since('public.planner_loads'::regclass) = v_since,
    'planner_state and planner_loads aren''t both frozen since the same moment';
  insert into t_mark values ('old', v_old);
  foreach v_sql in array array[
      'insert into public.planner_state (id, json, saved_at) values (''switch-test'', ''{}'', 1)',
      'update public.planner_state set saved_at = saved_at where id = ''main''',
      'delete from public.planner_state where id = ''switch-test''',
      'truncate public.planner_state',
      'insert into public.planner_loads (month, json, saved_at) values (''2099-12'', ''{}'', 1)',
      'update public.planner_loads set saved_at = saved_at',
      'delete from public.planner_loads where month = ''2099-12''',
      'truncate public.planner_loads'] loop
    refused := false;
    begin
      execute v_sql;
    exception when insufficient_privilege then
      get stacked diagnostics v_msg = message_text;
      refused := v_msg = format('frozen since %s; write to the tables', v_since);
    end;
    assert refused, format('not refused with "frozen since %s; write to the tables": %s', v_since, v_sql);
  end loop;
  assert not exists (select 1 from pg_catalog.pg_trigger x where x.tgname = 'adapter_mirror'
                      and x.tgrelid in ('public.planner_state'::regclass, 'public.planner_loads'::regclass)),
    'the side by side''s triggers are still there';
  assert not has_table_privilege('authenticated', 'public.planner_state', 'insert')
     and not has_table_privilege('authenticated', 'public.planner_state', 'update')
     and not has_table_privilege('authenticated', 'public.planner_loads', 'insert')
     and not has_table_privilege('authenticated', 'public.planner_loads', 'update')
     and not has_table_privilege('anon', 'public.planner_state', 'insert'), 'browsers can still write the old rows';
  -- a save through the adapter (as postgres, Claude's way): the tables change, the old rows don't, no job_runs row
  perform set_config('equinox.actor', 'claude', true), set_config('equinox.actor_detail', 'switch-over test', true);
  r := public.planner_item_put('dismissed', 'switch-over|test', '"2026-10-11"');
  perform set_config('equinox.actor', '', true), set_config('equinox.actor_detail', '', true);
  perform pg_temp.commit_triggers();
  assert (r ->> 'applied')::int = 1 and (pg_temp.doc() -> 'dismissed') ? 'switch-over|test', 'an item put through the adapter didn''t land';
  assert pg_temp.old_rows() = v_old, 'a save through the adapter changed planner_state or planner_loads';
  assert not exists (select 1 from public.job_runs where id > v_job), 'a save through the adapter still writes job_runs rows (the side by side)';
  insert into t_said values (1, format('frozen since %s: insert, update, delete and truncate refused on both old rows, from postgres too; browsers can''t write them; the side by side is off (a save through the adapter changes neither old row, no job_runs row)%s',
    v_since, case when switched then '; frozen during this rehearsal (the night of the switch-over)' else '' end));
end
$test$;
do $$ begin perform set_config('request.jwt.claims',
  '{"sub": "00000000-0000-4000-8000-0000000000f1", "email": "switch-over-staff@example.com", "role": "authenticated"}', true); end $$;
set local role authenticated;
do $test$
declare refused boolean := false;
begin
  begin
    update public.planner_state set saved_at = saved_at where id = 'main';
  exception when insufficient_privilege then refused := true;
  end;
  assert refused, 'signed in as staff, an update of planner_state wasn''t refused';
end
$test$;
reset role;

-- ---------------------------------------------------------------- 2. save_loads() and the capture's loads step
do $test$
declare w bigint := (select id from public.worlds where is_default); al text; al_id bigint; r jsonb; j jsonb; refused boolean;
  v_log bigint := coalesce((select max(id) from public.change_log), 0); v_old text := pg_temp.old_rows(); bad text;
begin
  select a.planner_name, a.id into al, al_id from public.airlines a join public.groups g on g.id = a.group_id
   where a.world_id = w and g.kind = 'ours' and a.active order by a.position limit 1;
  -- a day the capture filled: two captured flights on a test date
  insert into public.game_flights (world_id, airline_id, game_date, flight_no, dep_local, eco_pct, loads_captured_at)
  values (w, al_id, '2099-01-01', 9101, '08:00', 88, now() - interval '1 hour'), (w, al_id, '2099-01-01', 9102, '12:00', 91, now() - interval '1 hour'),
         (w, al_id, '2099-01-02', 9103, '08:00', 77, now() - interval '1 hour');
  j := pg_temp.month('2099-01');
  assert j #>> array['2099-01-01', 'f', al || '|9101'] = '88' and j #>> array['2099-01-02', 'f', al || '|9103'] = '77',
    'the getter doesn''t show the captured test flights';

  -- a whole day typed replaces that day's flights only
  r := public.save_loads('2099-01', jsonb_build_object('2099-01-02', jsonb_build_object('f', jsonb_build_object(al || '|9103', 60), 'done', true, 'savedAt', 10)));
  j := r -> 'json';
  assert j #>> array['2099-01-02', 'f', al || '|9103'] = '60' and (j #> array['2099-01-02', 'done'])::text = 'true',
    'a whole-day save didn''t set the day';
  assert j #>> array['2099-01-01', 'f', al || '|9101'] = '88', 'a whole-day save changed another day';
  assert j = pg_temp.month('2099-01') and (r ->> 'saved_at')::bigint = (select g.saved_at from public.planner_loads_get() g where g.month = '2099-01'),
    'save_loads() didn''t answer the month as planner_loads_get() gives it';
  -- a paste sets one flight and clears another, keeping the rest of the day
  r := public.save_loads('2099-01', jsonb_build_object('2099-01-01', jsonb_build_object('set', jsonb_build_object(al || '|9104', 70), 'del', jsonb_build_array(al || '|9102'))));
  j := r -> 'json';
  assert j #>> array['2099-01-01', 'f', al || '|9101'] = '88', 'a paste dropped a flight it didn''t touch';
  assert j #>> array['2099-01-01', 'f', al || '|9104'] = '70', 'a paste didn''t set the flight';
  assert not (j #> array['2099-01-01', 'f']) ? (al || '|9102'), 'a paste didn''t clear the flight';
  assert j #>> array['2099-01-02', 'f', al || '|9103'] = '60', 'a paste changed another day';
  -- a month nobody had yet
  r := public.save_loads('2099-02', jsonb_build_object('2099-02-03', jsonb_build_object('set', jsonb_build_object(al || '|10', 50), 'done', true)));
  assert pg_temp.month('2099-02') #>> array['2099-02-03', 'f', al || '|10'] = '50', 'a save to a new month wasn''t stored';
  -- bad input refused
  begin perform public.save_loads('2099-01', '{"2099-02-01": {"f": {}}}'); refused := false; exception when others then refused := true; end;
  assert refused, 'a day outside the month was accepted';
  -- only the load tables changed, as planner (save_loads); the old rows didn't
  select string_agg(distinct l.table_name || ' (' || l.actor || ', ' || coalesce(l.actor_detail, '') || ')', ', ') into bad
    from public.change_log l where l.id > v_log and not (l.table_name in ('load_entries', 'load_days') and l.actor = 'planner' and l.actor_detail = 'save_loads');
  assert bad is null, 'save_loads() wrote beyond load_entries and load_days as planner (save_loads): ' || bad;
  assert pg_temp.old_rows() = v_old, 'save_loads() changed planner_state or planner_loads';

  -- the capture's loads step: planner_loads untouched, and the getter shows the flight
  insert into public.game_flights (world_id, airline_id, game_date, flight_no, dep_local, eco_pct, loads_captured_at)
  values (w, al_id, current_date, 9105, '23:58', 57, now());
  r := private.apply_loads_from_capture(al_id);
  assert (r ->> 'days')::int = 0 and pg_temp.old_rows() = v_old, 'the capture''s loads step still writes planner_loads';
  assert pg_temp.month(to_char(current_date, 'YYYY-MM')) #>> array[current_date::text, 'f', al || '|9105'] = '57',
    'the getter doesn''t show the flight the capture just wrote';
  insert into t_said values (2, 'save_loads() writes only load_entries and load_days (planner, save_loads): a whole day replaced, single flights set and cleared, a new month, bad input refused, the answer the getter''s month; the capture''s loads step leaves planner_loads alone and the getter shows its flight');
end
$test$;
do $$ begin perform set_config('request.jwt.claims',
  '{"sub": "00000000-0000-4000-8000-0000000000f2", "email": "switch-over-other@example.com", "role": "authenticated"}', true); end $$;
do $test$
declare refused boolean := false;
begin
  begin perform public.save_loads('2099-01', '{}'); exception when insufficient_privilege then refused := true; end;
  assert refused, 'an account that isn''t staff could save loads';
end
$test$;

-- ---------------------------------------------------------------- 4. a save's base covers its whole millisecond
do $$ begin perform set_config('request.jwt.claims', '', true); end $$;
do $test$
declare d jsonb := pg_temp.doc(); z text; zdone boolean; base bigint; r jsonb;
begin
  select x.e ->> 'id', coalesce((x.e ->> 'done')::boolean, false) into z, zdone
    from jsonb_array_elements(d -> 'todos') with ordinality x(e, o) order by x.o desc limit 1;
  assert z is not null, 'the copy has no to-do';
  -- Claude changes to-do Z in a chat; a tab then loads (its base: planner_state_version(), in milliseconds rounded down)
  perform set_config('equinox.actor', 'claude', true), set_config('equinox.actor_detail', 'switch-over test', true);
  update public.todos set note = 'switch-over test: Claude' where legacy_key = z and world_id = (select id from public.worlds where is_default);
  perform set_config('equinox.actor', '', true), set_config('equinox.actor_detail', '', true);
  base := public.planner_state_version();
  assert base = (select floor(extract(epoch from max(changed_at)) * 1000)::bigint from public.change_log), 'the version isn''t the latest change''s millisecond';
  d := pg_temp.doc();
  -- the tab ticks (or unticks) Z: Claude's change is in what it loaded, so it isn't skipped
  r := public.planner_state_put(pg_temp.with_todo(d, z, jsonb_build_object('done', not zdone))::text, pg_temp.ms(), base, 'switch-over-tab');
  assert (r ->> 'applied')::int = 1 and (r ->> 'skipped')::int = 0 and not (r ->> 'reload')::boolean,
    format('a tab that loaded Claude''s change was told to reload when it changed that to-do (applied %s, skipped %s)', r ->> 'applied', r ->> 'skipped');
  -- Claude again, after that base: a save from it skips the to-do
  perform pg_sleep(0.002);
  perform set_config('equinox.actor', 'claude', true), set_config('equinox.actor_detail', 'switch-over test', true);
  update public.todos set note = 'switch-over test: Claude again' where legacy_key = z and world_id = (select id from public.worlds where is_default);
  perform set_config('equinox.actor', '', true), set_config('equinox.actor_detail', '', true);
  r := public.planner_state_put(pg_temp.with_todo(d, z, jsonb_build_object('done', zdone))::text, pg_temp.ms(), (r ->> 'saved_at')::bigint, 'switch-over-tab');
  assert (r ->> 'skipped')::int = 1 and (r ->> 'reload')::boolean, 'a change made after the tab''s base wasn''t skipped';
  insert into t_said values (4, 'a save''s base covers its millisecond: a tab that loaded Claude''s change can change that to-do itself; a later change is still skipped');
end
$test$;

-- ---------------------------------------------------------------- 3 and 5. with the freeze lifted, as a rollback lifts it
do $$ begin perform set_config('request.jwt.claims',
  '{"sub": "00000000-0000-4000-8000-0000000000f1", "email": "switch-over-staff@example.com", "role": "authenticated"}', true); end $$;
do $test$
declare w bigint := (select id from public.worlds where is_default); res jsonb; g jsonb; v_job bigint; j record; bad text;
  i int; tid text; d jsonb; al text; al_id bigint; r jsonb;
begin
  -- a to-do ticked and a load typed through the adapter first, so the rollback has something to carry
  d := pg_temp.doc();
  select (x.o - 1)::int, x.e ->> 'id' into i, tid from jsonb_array_elements(d -> 'todos') with ordinality x(e, o)
   where not coalesce((x.e ->> 'done')::boolean, false) order by x.o limit 1;
  if tid is not null then
    r := public.planner_state_put(pg_temp.with_todo(d, tid, '{"done": true, "doneAt": "2026-10-11T02:00:00.000Z"}')::text, pg_temp.ms(),
                                  public.planner_state_version(), 'switch-over-tab');
  end if;
  select a.planner_name, a.id into al, al_id from public.airlines a join public.groups g on g.id = a.group_id
   where a.world_id = w and g.kind = 'ours' and a.active order by a.position limit 1;
  r := public.save_loads(to_char(current_date - 1, 'YYYY-MM'),
         jsonb_build_object((current_date - 1)::text, jsonb_build_object('set', jsonb_build_object(al || '|9106', 66))));
  assert pg_temp.old_rows() = (select v from t_mark where k = 'old'), 'the old rows changed before the rollback';

  -- the rollback
  res := private.unfreeze_planner_state();
  g := public.planner_state_get();
  assert (select json::jsonb from public.planner_state where id = 'main') = (g ->> 'json')::jsonb
     and (select saved_at from public.planner_state where id = 'main') = (g ->> 'saved_at')::bigint,
    'after private.unfreeze_planner_state(), planner_state isn''t planner_state_get() exactly';
  select string_agg(coalesce(o.month, n.month), ', ') into bad
    from (select * from public.planner_loads pl where pl.month in (select month from public.planner_loads_get())) o
    full join public.planner_loads_get() n on n.month = o.month
   where o.month is null or n.month is null or o.json::jsonb <> n.json::jsonb or o.saved_at <> n.saved_at;
  assert bad is null, 'after private.unfreeze_planner_state(), these planner_loads months aren''t the getter''s exactly: ' || bad;
  assert (tid is null or (select json::jsonb from public.planner_state) #>> array['todos', i::text, 'done'] = 'true')
     and (select json::jsonb from public.planner_loads where month = to_char(current_date - 1, 'YYYY-MM')) #>> array[(current_date - 1)::text, 'f', al || '|9106'] = '66',
    'the saves made since the switch aren''t in the old rows after the rollback';
  assert private.planner_frozen_since('public.planner_state'::regclass) is null and private.planner_frozen_since('public.planner_loads'::regclass) is null,
    'the freeze is still on after private.unfreeze_planner_state()';
  assert has_table_privilege('authenticated', 'public.planner_state', 'insert') and has_table_privilege('authenticated', 'public.planner_state', 'update'),
    'staff didn''t get planner_state''s writes back';
  assert (select count(*) from pg_catalog.pg_trigger x where x.tgname = 'adapter_mirror'
           and x.tgrelid in ('public.planner_state'::regclass, 'public.planner_loads'::regclass)) = 2,
    'the side by side''s triggers aren''t back';

  -- the old planner saves the old row again (a to-do's title, as its upsert does): copied into the tables, comparison ok
  v_job := coalesce((select max(id) from public.job_runs), 0);
  d := (select json::jsonb from public.planner_state where id = 'main');
  update public.planner_state set json = jsonb_set(d, '{todos,0,title}', to_jsonb('after the rollback: ' || (d #>> '{todos,0,title}')))::text,
         saved_at = saved_at + 1000 where id = 'main';
  perform pg_temp.commit_triggers();
  for j in select * from public.job_runs where id > v_job loop
    assert j.status = 'ok', format('%s after the old planner saved again: %s', j.job, j.note);
  end loop;
  assert (select count(*) from public.job_runs where id > v_job) = 2, 'the old planner''s save wasn''t copied and compared once each';
  assert pg_temp.doc() #>> '{todos,0,title}' = 'after the rollback: ' || (d #>> '{todos,0,title}'), 'the old planner''s save didn''t reach the tables';
  -- save_loads() and the capture's loads step write planner_loads again
  r := public.save_loads(to_char(current_date - 1, 'YYYY-MM'),
         jsonb_build_object((current_date - 1)::text, jsonb_build_object('set', jsonb_build_object(al || '|9107', 67))));
  assert (select json::jsonb from public.planner_loads where month = to_char(current_date - 1, 'YYYY-MM')) #>> array[(current_date - 1)::text, 'f', al || '|9107'] = '67',
    'after the rollback, save_loads() doesn''t write planner_loads';
  insert into t_said values (5, format('rollback: private.unfreeze_planner_state() made planner_state and %s planner_loads month(s) the getters'' exactly (the saves since the switch included), lifted the freeze, gave staff back planner_state''s writes and put the side by side back; the old planner''s save was then copied and compared ok, and save_loads() writes planner_loads again',
    res ->> 'planner_loads_months'));
end
$test$;

-- 3. a loads day's done, part-way through an evening's capture (with the freeze lifted, so the capture's loads step
-- writes planner_loads and the two can be compared)
do $test$
declare w bigint := (select id from public.worlds where is_default); day date := '2099-03-10'; a record; n int := 0; k int;
  v_start timestamptz; g_done boolean; c_done boolean; first_al bigint;
begin
  v_start := (day + time '10:00') at time zone 'UTC';
  assert (select (s.value #>> '{}') from public.settings s where s.world_id = w and s.airline_id is null and s.key = 'capture_day_starts_utc') = '10:00',
    'the capture day doesn''t start at 10:00 UTC on the copy';
  select count(*) into k from public.airlines x join public.groups g on g.id = x.group_id
   where x.world_id = w and x.active and g.kind = 'ours';
  -- the evening before: every airline's loads page had flights of the day (captured in the evening before's capture day)
  insert into public.game_flights (world_id, airline_id, game_date, flight_no, dep_local, eco_pct, loads_captured_at)
  select w, x.id, day, 9500 + (x.id % 400)::int, '06:00', 50, v_start - interval '6 hours'
    from public.airlines x join public.groups g on g.id = x.group_id where x.world_id = w and x.active and g.kind = 'ours';
  first_al := (select x.id from public.airlines x join public.groups g on g.id = x.group_id
                where x.world_id = w and x.active and g.kind = 'ours' order by x.position limit 1);
  perform private.apply_loads_from_capture(first_al);
  g_done := (pg_temp.month('2099-03') #> array[day::text, 'done'])::text = 'true';
  c_done := (select json::jsonb #> array[day::text, 'done'] from public.planner_loads where month = '2099-03')::text = 'true';
  assert not g_done and not c_done, format('with only the evening before''s loads, the day is done (getter %s, capture %s)', g_done, c_done);
  -- the evening itself, one airline at a time: its loads page, which brings that day's flights again
  for a in select x.id, x.position from public.airlines x join public.groups g on g.id = x.group_id
            where x.world_id = w and x.active and g.kind = 'ours' order by x.position loop
    n := n + 1;
    insert into public.game_capture_raw (world_id, airline_id, airline, kind, rows, captured_at)
    values (w, a.id, 'switch-over test', 'loads', '[]', v_start + interval '12 hours' + n * interval '3 minutes');
    update public.game_flights set loads_captured_at = v_start + interval '12 hours' + n * interval '3 minutes', eco_pct = 60
     where airline_id = a.id and game_date = day;
    perform private.apply_loads_from_capture(a.id);
    g_done := (pg_temp.month('2099-03') #> array[day::text, 'done'])::text = 'true';
    c_done := (select json::jsonb #> array[day::text, 'done'] from public.planner_loads where month = '2099-03')::text = 'true';
    assert g_done = c_done, format('after %s of %s airlines, the getter says done %s and the capture''s loads step %s', n, k, g_done, c_done);
    assert g_done = (n = k), format('after %s of %s airlines, the day''s done is %s', n, k, g_done);
  end loop;
  -- a day typed done is done, whatever the capture
  perform public.save_loads('2099-03', jsonb_build_object('2099-03-20', jsonb_build_object('f', '{}'::jsonb, 'done', true)));
  assert (pg_temp.month('2099-03') #> '{2099-03-20,done}')::text = 'true', 'a day typed done isn''t done';
  insert into t_said values (3, format('a loads day''s done, one rule: part-way through an evening''s capture (1 to %s of %s airlines in) the getter and the capture''s loads step both say not done; once the last is in, both say done; a day typed done is done', k - 1, k));
end
$test$;

-- 5b. freezing again (a switch-over after a rollback)
do $test$
declare v text;
begin
  v := private.freeze_planner_state();
  assert private.planner_frozen_since('public.planner_state'::regclass) = v and private.planner_frozen_since('public.planner_loads'::regclass) = v,
    'private.freeze_planner_state() didn''t freeze both old rows again';
  begin
    update public.planner_state set saved_at = saved_at where id = 'main';
    assert false, 'planner_state took a write after freezing again';
  exception when insufficient_privilege then null;
  end;
end
$test$;
do $$ begin perform set_config('request.jwt.claims', '', true); end $$;

-- ---------------------------------------------------------------- 6. who may call the new functions
do $test$
begin
  assert has_function_privilege('authenticated', 'public.loads_day_captured(bigint, date)', 'execute')
     and not has_function_privilege('anon', 'public.loads_day_captured(bigint, date)', 'execute'),
    'loads_day_captured() isn''t staff-callable only';
  assert not has_function_privilege('authenticated', 'private.unfreeze_planner_state()', 'execute')
     and not has_function_privilege('authenticated', 'private.freeze_planner_state()', 'execute')
     and not has_function_privilege('anon', 'private.unfreeze_planner_state()', 'execute')
     and not has_function_privilege('authenticated', 'private.planner_frozen_since(regclass)', 'execute'),
    'the freeze''s functions are open to the data API''s roles';
  assert (select bool_and(not p.prosecdef and coalesce('search_path=""' = any (p.proconfig), false)) from pg_proc p
           where p.oid in ('private.unfreeze_planner_state()'::regprocedure, 'private.freeze_planner_state()'::regprocedure,
                           'private.planner_frozen()'::regprocedure, 'private.planner_frozen_since(regclass)'::regprocedure,
                           'public.loads_day_captured(bigint, date)'::regprocedure)),
    'a new function runs as owner, or without an empty search path';
end
$test$;
do $$ begin perform set_config('request.jwt.claims',
  '{"sub": "00000000-0000-4000-8000-0000000000f2", "email": "switch-over-other@example.com", "role": "authenticated"}', true); end $$;
set local role authenticated;
do $test$
declare refused boolean := false;
begin
  begin perform public.loads_day_captured((select id from public.worlds where is_default), current_date); exception when insufficient_privilege then refused := true; end;
  assert refused, 'an account that isn''t staff could call loads_day_captured()';
end
$test$;
reset role;
do $$ begin perform set_config('request.jwt.claims', '', true); end $$;

-- ---------------------------------------------------------------- what was checked, in four lines
do $test$
begin
  raise notice '%', (select line from t_said where part = 1);
  raise notice '%', (select line from t_said where part = 2);
  raise notice '%', (select line from t_said where part = 3);
  raise notice '%; %', (select line from t_said where part = 4), (select line from t_said where part = 5);
end
$test$;

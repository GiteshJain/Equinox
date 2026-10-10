-- Side by side (#13 build, pull request 5; design §9): the triggers on planner_state and planner_loads. Run by
-- database/rehearse.sh on the copy of last night's backup, after the new migrations, inside a transaction that is rolled
-- back. A failed check stops with an error that says where (ids, paths and counts, never values).
-- The switch-over (pull request 9) took the side by side away; a rollback puts it back. So this test first rolls back
-- inside its own transaction (private.unfreeze_planner_state()) and checks the side by side as the rollback leaves it.
--   1. A save of planner_state (a to-do ticked, as the planner saves it) is copied into the tables (actor planner,
--      detail mirror) and the comparison is ok: one job_runs row each. A tab opened before the evening's capture and
--      saved after it now fails the comparison where its document lacks the capture's figure (the cash allowances ended
--      at the switch-over); a typed figure the mirror didn't store fails it too. Two blank cabin layouts are both kept;
--      a code listed twice fails the comparison, named first in its note.
--   2. Loads: save_loads() as staff writes load_entries and load_days itself (actor planner, detail save_loads), and the
--      capture's loads step is followed too; each write's comparison is ok.
--   3. The trigger never blocks a save: with the mirror made to fail on purpose, planner_state and planner_loads still
--      save, and a failed mirror and a failed comparison (saying where) land in job_runs.
--   4. Clean days: adapter_clean_days() over hand-made job_runs rows (a clean day, a day with a failure, a day with no
--      comparison).
--   5. Speed: the trigger's added time on a planner save, best of 3.
--   6. Access: job_runs and adapter_check_days read by staff only; signed out nothing.
-- The triggers run when a transaction commits. This test is one transaction that is rolled back, so after each write it
-- runs them as a commit would (pg_temp.commit_triggers: set constraints all immediate, then deferred again).

create function pg_temp.jobs_since(p_id bigint) returns table (job text, status text, note text, details jsonb) language sql as $$
  select j.job, j.status, j.note, j.details from public.job_runs j where j.id > p_id order by j.id
$$;
create function pg_temp.commit_triggers() returns void language plpgsql as $$
begin
  execute 'set constraints all immediate';
  execute 'set constraints all deferred';
end
$$;
create temporary table t_mark (k text primary key, v bigint) on commit drop;
-- what each part checked, printed at the end as four lines (the rehearsal shows a test's first four), speed first
create temporary table t_said (part int primary key, line text) on commit drop;
insert into public.planner_users (email) values ('side-by-side-staff@example.com') on conflict do nothing;
-- the side by side as a rollback puts it back
do $$ begin
  if private.planner_frozen_since('public.planner_state'::regclass) is not null then perform private.unfreeze_planner_state(); end if;
end $$;

-- ---------------------------------------------------------------- 1. a planner_state save
do $test$
declare d jsonb; i int; tid text; v_job bigint := coalesce((select max(id) from public.job_runs), 0);
  v_log bigint := coalesce((select max(id) from public.change_log), 0); r record; n int;
begin
  select p.json::jsonb into d from public.planner_state p where p.id = 'main';
  select (e.ord - 1)::int, e.v ->> 'id' into i, tid from jsonb_array_elements(d -> 'todos') with ordinality e(v, ord)
   where not coalesce((e.v ->> 'done')::boolean, false) order by e.ord limit 1;
  assert i is not null, 'the copy has no open to-do';
  update public.planner_state
     set json = jsonb_set(jsonb_set(d, array['todos', i::text, 'done'], 'true'), array['todos', i::text, 'doneAt'], '"2026-10-10T20:15:42.318Z"')::text,
         saved_at = saved_at + 1000
   where id = 'main';
  assert not exists (select 1 from pg_temp.jobs_since(v_job)), 'the side by side ran before the save''s transaction committed';
  perform pg_temp.commit_triggers();
  select count(*) into n from pg_temp.jobs_since(v_job);
  assert n = 2, format('a planner_state save wrote %s job_runs rows, expected 2 (a mirror and a comparison)', n);
  for r in select * from pg_temp.jobs_since(v_job) loop
    assert r.status = 'ok', format('%s after a planner_state save: %s', r.job, r.note);
  end loop;
  assert (select count(*) from public.change_log l where l.id > v_log) = 1
     and exists (select 1 from public.change_log l join public.todos t on l.row_key = jsonb_build_object('id', t.id)
                  where l.id > v_log and l.table_name = 'todos' and t.legacy_key = tid and l.op = 'update'
                    and l.actor = 'planner' and l.actor_detail = 'mirror' and l.new_values ?& array['done', 'done_at']
                    and not (l.new_values ?| array['title', 'note', 'due_on', 'extra'])),
    'the mirror didn''t write exactly the ticked to-do''s done and done_at, as planner (mirror)';
  insert into t_mark values ('state job', v_job);
  insert into t_said values (1, format('a planner_state save (to-do %s ticked): copied as one change to todos (planner, mirror), comparison ok', tid));
end
$test$;

-- ---------------------------------------------------------------- 1b. a planner tab opened before the evening's capture
-- Saved after the capture, its document has no figure for a date the capture filled since. Until the switch-over the
-- comparison allowed it (the Building chat's call, 10 Oct); the cash allowances ended with the switch-over, so after a
-- rollback it fails there, at that date's cash (the mirror itself is ok). A typed figure the mirror failed to store
-- fails the comparison too.
alter table public.cash_entries add constraint side_by_side_test_cash check (cash is distinct from 4321000);
do $test$
declare w bigint := (select id from public.worlds where is_default); d jsonb; v_job bigint; j record; al text; al_id bigint;
  day date := '2099-07-01'; v_saved bigint;
begin
  select a.planner_name, a.id into al, al_id from public.airlines a join public.groups g on g.id = a.group_id
   where a.world_id = w and g.kind = 'ours' and a.active order by a.position limit 1;
  select p.json::jsonb into d from public.planner_state p where p.id = 'main';
  assert d #> array['cash', day::text] is null and d #> array['fixed7', day::text] is null, 'the copy''s planner already has the test date';
  -- the evening's capture: that airline's balance for that date, captured an hour before the tab saves
  insert into public.game_balance (airline, captured_on, account, amount, captured_at, world_id, airline_id, capture_day)
  values (al, day, '2800 Bank account', 1234567, now() - interval '1 hour', w, al_id, day);
  -- the tab, opened before it, saves a to-do's title
  v_saved := greatest((select saved_at from public.planner_state where id = 'main') + 1000, (extract(epoch from clock_timestamp()) * 1000)::bigint);
  v_job := (select max(id) from public.job_runs);
  update public.planner_state set json = jsonb_set(d, '{todos,0,title}', to_jsonb('stale tab: ' || (d #>> '{todos,0,title}')))::text,
         saved_at = v_saved
   where id = 'main';
  perform pg_temp.commit_triggers();
  assert (select status from pg_temp.jobs_since(v_job) where job = 'adapter_mirror') = 'ok', 'the stale tab''s save wasn''t copied';
  select * into j from pg_temp.jobs_since(v_job) where job = 'adapter_check';
  assert j.status = 'failed' and j.note like '%$.cash.{}%' and not (j.details -> 'allowed') ? 'cash/fixed7 captured, not in the saved document',
    'a stale tab''s document without the capture''s figure didn''t fail the comparison at that date''s cash: ' || coalesce(j.note, 'no row');

  -- the same tab types a figure for that date, and the mirror fails to store it (the check above)
  v_job := (select max(id) from public.job_runs);
  update public.planner_state
     set json = jsonb_set(json::jsonb, '{cash}', coalesce(json::jsonb -> 'cash', '{}') || jsonb_build_object(day::text, jsonb_build_object(al, 4.321)))::text,
         saved_at = saved_at + 1000
   where id = 'main';
  perform pg_temp.commit_triggers();
  assert (select status from pg_temp.jobs_since(v_job) where job = 'adapter_mirror') = 'failed', 'the mirror stored the figure it was made to fail on';
  select * into j from pg_temp.jobs_since(v_job) where job = 'adapter_check';
  assert j.status = 'failed' and j.note like '%$.cash.{}%' and j.details -> 'cash' ->> 0 like format('cash %s %s (the figure differs;%%', day, al),
    'a typed figure the mirror didn''t store didn''t fail the comparison: ' || coalesce(j.note, 'no row');
  insert into t_said values (4, 'a tab opened before the evening''s capture and saved after it: copied, and its comparison fails at that date''s cash (the allowance ended at the switch-over); a typed figure the mirror didn''t store fails it too');
end
$test$;
alter table public.cash_entries drop constraint side_by_side_test_cash;
-- the test's capture goes again, so the parts below don't meet its figure (no allowance takes it any more)
delete from public.game_balance where captured_on = '2099-07-01' and account = '2800 Bank account' and amount = 1234567;

-- ---------------------------------------------------------------- 1c. a code the planner lists twice
-- Two cabin layouts with the same blank code (as "Add config" adds them) are both kept. Two with the same code that
-- isn't blank stay unsupported: the tables keep the first, and the comparison's note says so first, plainly.
do $test$
declare d jsonb; v_job bigint; j record; v_code text; v_blank int := (select count(*) from public.cabin_configs where code = 'NEW');
begin
  select p.json::jsonb into d from public.planner_state p where p.id = 'main';
  v_code := d #>> '{ref,configs,0,code}';
  v_job := (select max(id) from public.job_runs);
  update public.planner_state
     set json = jsonb_set(d, '{ref,configs}', (d #> '{ref,configs}')
                          || '[{"code": "NEW", "type": "", "cabin": "", "seats": 0}, {"code": "NEW", "type": "", "cabin": "", "seats": 0}]')::text,
         saved_at = saved_at + 1000
   where id = 'main';
  perform pg_temp.commit_triggers();
  for j in select * from pg_temp.jobs_since(v_job) loop
    assert j.status = 'ok', format('%s after two blank layouts were added: %s', j.job, j.note);
  end loop;
  assert (select count(*) from public.cabin_configs where code = 'NEW') = v_blank + 2, 'the two blank layouts aren''t two rows';

  v_job := (select max(id) from public.job_runs);
  update public.planner_state
     set json = jsonb_set(d, '{ref,configs}', (d #> '{ref,configs}')
                          || jsonb_build_array((d #> '{ref,configs,0}') || '{"note": "side by side: the same code twice"}'))::text,
         saved_at = saved_at + 1000
   where id = 'main';
  perform pg_temp.commit_triggers();
  select * into j from pg_temp.jobs_since(v_job) where job = 'adapter_check';
  assert j.status = 'failed' and j.note like format('duplicate code %s in ref.configs; planner_state differs at: %%', v_code),
    'a code listed twice isn''t named first in the comparison''s note: ' || coalesce(j.note, 'no row');
  -- back as it was
  update public.planner_state set json = d::text, saved_at = saved_at + 1000 where id = 'main';
  perform pg_temp.commit_triggers();
  insert into t_said values (5, format('two blank layouts both kept, comparison ok; a code listed twice fails it, named first ("duplicate code %s in ref.configs")', v_code));
end
$test$;

-- ---------------------------------------------------------------- 2. loads: save_loads() and the capture's loads step
do $$ begin perform set_config('request.jwt.claims',
  '{"sub": "00000000-0000-4000-8000-0000000000e1", "email": "side-by-side-staff@example.com", "role": "authenticated"}', true); end $$;
do $test$
declare w bigint := (select id from public.worlds where is_default); al text; al_id bigint; v_job bigint := coalesce((select max(id) from public.job_runs), 0);
  v_log bigint := coalesce((select max(id) from public.change_log), 0); r jsonb; j record; day date := current_date - 1; mon text; n int;
begin
  select a.planner_name, a.id into al, al_id from public.airlines a join public.groups g on g.id = a.group_id
   where a.world_id = w and g.kind = 'ours' and a.active order by a.position limit 1;
  mon := to_char(day, 'YYYY-MM');
  -- a typed load, as the planner sends it (one flight, done, savedAt)
  r := public.save_loads(mon, jsonb_build_object(day::text, jsonb_build_object('set', jsonb_build_object(al || '|9871', 63), 'savedAt', 1791700000000)));
  perform pg_temp.commit_triggers();
  assert (r -> 'json' #>> array[day::text, 'f', al || '|9871']) = '63', 'save_loads() didn''t return the typed load';
  assert exists (select 1 from public.load_entries e where e.airline_id = al_id and e.game_date = day and e.flight_no = 9871 and e.eco_pct = 63),
    'save_loads() didn''t write the typed load to load_entries';
  assert not exists (select 1 from public.change_log l where l.id > v_log and l.table_name in ('load_entries', 'load_days')
                        and (l.actor <> 'planner' or l.actor_detail <> 'save_loads')),
    'save_loads()''s table writes aren''t named planner (save_loads)';
  assert not exists (select 1 from public.change_log l where l.id > v_log and l.table_name not in ('load_entries', 'load_days')),
    'save_loads() changed other tables';
  for j in select * from pg_temp.jobs_since(v_job) loop
    assert j.status = 'ok', format('%s after save_loads(): %s', j.job, j.note);
  end loop;
  select count(*) into n from pg_temp.jobs_since(v_job) where job = 'adapter_check';
  assert n = 1, format('save_loads() was compared %s times, expected once', n);

  -- the capture's loads step, for a flight captured today
  v_job := (select max(id) from public.job_runs);
  insert into public.game_flights (world_id, airline_id, game_date, flight_no, dep_local, eco_pct, loads_captured_at)
  values (w, al_id, current_date, 9872, '10:00', 57, now());
  perform private.apply_loads_from_capture(al_id);
  perform pg_temp.commit_triggers();
  select count(*) into n from pg_temp.jobs_since(v_job) where job = 'adapter_check';
  assert n = (select count(distinct to_char(f.game_date, 'YYYY-MM')) from public.game_flights f
               where f.airline_id = al_id and f.flight_no is not null and f.game_date >= current_date - 3),
    format('the capture''s loads step was compared %s times, not once per month it wrote', n);
  for j in select * from pg_temp.jobs_since(v_job) loop
    assert j.status = 'ok', format('%s after the capture''s loads step: %s', j.job, j.note);
  end loop;
  insert into t_said values (2, format('save_loads() wrote load_entries itself (planner, save_loads), comparison ok; the capture''s loads step: %s comparison(s), all ok', n));
end
$test$;

-- part-way through an evening's capture (the bug the first rehearsal found: the getter and the capture's loads step used
-- different rules for a day's done, so the mirror had to copy the old row's flag in again). Since the switch-over both
-- follow one rule (public.loads_day_captured): with every airline's flights of the day captured only the evening
-- before, and the first airline's loads page of the day in, both say the day isn't done, and the comparison finds no
-- difference in it.
do $test$
declare w bigint := (select id from public.worlds where is_default); mon text := to_char(current_date + 20, 'YYYY-MM');
  d date := current_date + 20; v_job bigint; j record; first_al bigint; v_start timestamptz;
begin
  v_start := (d + time '10:00') at time zone 'UTC';
  -- a test airline of ours, so its loads step touches only the test day
  insert into public.airlines (world_id, group_id, game_id, planner_name, iata_code, active)
  select w, g.id, 999031, 'Side Test Air', 'ST', true from public.groups g where g.world_id = w and g.kind = 'ours' order by g.id limit 1
  returning id into first_al;
  insert into public.game_flights (world_id, airline_id, game_date, flight_no, dep_local, eco_pct, loads_captured_at)
  select w, a.id, d, 9800 + (a.id % 100)::int, '06:00', 50, v_start - interval '6 hours' from public.airlines a join public.groups g on g.id = a.group_id
   where a.world_id = w and a.active and g.kind = 'ours';
  insert into public.game_capture_raw (world_id, airline_id, airline, kind, rows, captured_at)
  values (w, first_al, 'side by side test', 'loads', '[]', v_start + interval '12 hours');
  update public.game_flights set loads_captured_at = v_start + interval '12 hours' where airline_id = first_al and game_date = d;
  v_job := (select max(id) from public.job_runs);
  perform private.apply_loads_from_capture(first_al);
  perform pg_temp.commit_triggers();
  -- (the hand-made day differs in its stamps and in the flights only the evening before's capture wrote, which this test
  -- skips; what matters here is the day's done)
  for j in select * from pg_temp.jobs_since(v_job) loop
    assert j.note not like '%.done%' and (j.job <> 'adapter_mirror' or j.status = 'ok'), format('%s part-way through a capture: %s', j.job, j.note);
  end loop;
  assert exists (select 1 from pg_temp.jobs_since(v_job) where job = 'adapter_check'), 'part-way through a capture, the loads step wasn''t compared';
  assert (select json::jsonb #> array[d::text, 'done'] from public.planner_loads where month = mon) = 'false'::jsonb
     and (select g.json::jsonb #> array[d::text, 'done'] from public.planner_loads_get(w) g where g.month = mon) = 'false'::jsonb,
    'part-way through a capture, the capture''s loads step or the getter says the day is done';
  insert into t_said values (3, 'part-way through a capture, the capture''s loads step and the getter both say the day isn''t done (one rule), and the comparison finds no difference in it');
end
$test$;
do $$ begin perform set_config('request.jwt.claims', '', true); end $$;

-- ---------------------------------------------------------------- 3. the trigger never blocks a save
alter table public.todos add constraint side_by_side_test_fails check (title <> 'side by side: the mirror must fail');
alter table public.load_entries add constraint side_by_side_test_fails check (eco_pct is distinct from 41.5);
do $test$
declare d jsonb; v_job bigint := coalesce((select max(id) from public.job_runs), 0); r record; mon text := to_char(current_date - 1, 'YYYY-MM');
  al text := (select a.planner_name from public.airlines a join public.groups g on g.id = a.group_id
               where a.world_id = (select id from public.worlds where is_default) and g.kind = 'ours' order by a.position limit 1);
  doc jsonb;
begin
  select p.json::jsonb into d from public.planner_state p where p.id = 'main';
  update public.planner_state set json = jsonb_set(d, '{todos,0,title}', '"side by side: the mirror must fail"')::text, saved_at = saved_at + 1000
   where id = 'main';
  perform pg_temp.commit_triggers();
  assert (select json::jsonb #>> '{todos,0,title}' from public.planner_state where id = 'main') = 'side by side: the mirror must fail',
    'the planner_state save didn''t go through';
  select * into r from pg_temp.jobs_since(v_job) where job = 'adapter_mirror';
  assert r.status = 'failed' and r.note like 'planner_state: %side_by_side_test_fails%', 'the failed mirror wasn''t recorded: ' || coalesce(r.note, 'no row');
  select * into r from pg_temp.jobs_since(v_job) where job = 'adapter_check';
  assert r.status = 'failed' and r.note like '%$.todos[].title%' and r.details -> 'paths' ? '$.todos[0].title',
    'the comparison after a failed mirror didn''t fail at the to-do''s title: ' || coalesce(r.note, 'no row');

  -- planner_loads: the capture writing a day the mirror can't copy still saves
  v_job := (select max(id) from public.job_runs);
  select coalesce((select json::jsonb from public.planner_loads where month = mon), '{}'::jsonb) into doc;
  doc := jsonb_set(doc, array[(current_date - 1)::text], jsonb_build_object('done', true, 'f', jsonb_build_object(al || '|9873', 41.5)));
  insert into public.planner_loads (month, json, saved_at) values (mon, doc::text, 1791700000001)
  on conflict (month) do update set json = excluded.json, saved_at = excluded.saved_at;
  perform pg_temp.commit_triggers();
  assert (select json::jsonb #> array[(current_date - 1)::text, 'f', al || '|9873'] from public.planner_loads where month = mon) = '41.5',
    'the planner_loads write didn''t go through';
  assert exists (select 1 from pg_temp.jobs_since(v_job) where job = 'adapter_mirror' and status = 'failed'),
    'the failed loads mirror wasn''t recorded';
  assert exists (select 1 from pg_temp.jobs_since(v_job) where job = 'adapter_check' and status = 'failed' and note like '%.f.{flight}%'),
    'the loads comparison after a failed mirror didn''t fail at the flight';
  insert into t_said values (6, 'the trigger never blocks a save: with the mirror made to fail, planner_state and planner_loads saved, and failed mirror and comparison rows say where');
end
$test$;
alter table public.todos drop constraint side_by_side_test_fails;
alter table public.load_entries drop constraint side_by_side_test_fails;

-- ---------------------------------------------------------------- 4. clean days, over hand-made rows
do $test$
declare w bigint := (select id from public.worlds where is_default);
begin
  -- capture days (10:00 to 10:00 UTC) in 2099: the 10th clean, the 9th clean, the 8th a failure, the 7th clean, the 6th
  -- clean but the 5th has only a mirror (no comparison), the 4th clean
  insert into public.job_runs (job, world_id, started_at, finished_at, status, for_day) values
    ('adapter_mirror', w, '2099-06-10 12:00Z', '2099-06-10 12:00Z', 'ok', '2099-06-10'),
    ('adapter_check', w, '2099-06-10 12:00Z', '2099-06-10 12:00Z', 'ok', '2099-06-10'),
    ('adapter_check', w, '2099-06-10 09:00Z', '2099-06-10 09:00Z', 'ok', '2099-06-09'),
    ('adapter_check', w, '2099-06-08 12:00Z', '2099-06-08 12:00Z', 'ok', '2099-06-08'),
    ('adapter_check', w, '2099-06-08 13:00Z', '2099-06-08 13:00Z', 'failed', '2099-06-08'),
    ('adapter_check', w, '2099-06-07 12:00Z', '2099-06-07 12:00Z', 'ok', '2099-06-07'),
    ('adapter_check', w, '2099-06-06 12:00Z', '2099-06-06 12:00Z', 'ok', '2099-06-06'),
    ('adapter_mirror', w, '2099-06-05 12:00Z', '2099-06-05 12:00Z', 'ok', '2099-06-05'),
    ('adapter_check', w, '2099-06-04 12:00Z', '2099-06-04 12:00Z', 'ok', '2099-06-04');
  assert public.adapter_clean_days(w, '2099-06-10 15:00Z') = 2, format('on the 10th: %s clean days, expected 2 (10th, 9th; the 8th failed)', public.adapter_clean_days(w, '2099-06-10 15:00Z'));
  assert public.adapter_clean_days(w, '2099-06-11 11:00Z') = 2, 'the 11th, with no run yet, broke the run or counted';
  assert public.adapter_clean_days(w, '2099-06-12 11:00Z') = 0, 'a whole day with no comparison didn''t end the run';
  assert public.adapter_clean_days(w, '2099-06-08 15:00Z') = 0, 'a day with a failure counted';
  assert public.adapter_clean_days(w, '2099-06-07 15:00Z') = 2, 'the 7th and 6th aren''t 2 clean days';
  assert public.adapter_clean_days(w, '2099-06-05 15:00Z') = 0, 'a day with a mirror but no comparison counted as clean';
  assert public.adapter_clean_days(w, '2099-06-04 15:00Z') = 1, 'a single clean day didn''t count';
  -- an hour before the day starts (09:00 UTC on the 10th belongs to the 9th)
  assert public.adapter_clean_days(w, '2099-06-10 09:30Z') = 1, 'the capture day didn''t start at 10:00 UTC';
  assert (select clean from public.adapter_check_days where world_id = w and day = '2099-06-08') = false
     and (select comparisons from public.adapter_check_days where world_id = w and day = '2099-06-10') = 1,
    'adapter_check_days counts wrong';
  insert into t_said values (7, 'clean days counted right over hand-made rows (a clean day, a day with a failure, one with only a mirror, one with nothing)');
end
$test$;

-- ---------------------------------------------------------------- 5. speed: the trigger's added time on a planner save
do $test$
declare d jsonb; i int; t0 timestamptz; with_ms numeric[] := '{}'; without_ms numeric[] := '{}'; k int; added numeric;
begin
  select p.json::jsonb into d from public.planner_state p where p.id = 'main';
  i := (select (e.ord - 1)::int from jsonb_array_elements(d -> 'todos') with ordinality e(v, ord) order by e.ord limit 1);
  -- each save ticks or unticks one to-do, as a click in the planner does, and commits (the triggers run then)
  for k in 1 .. 4 loop
    t0 := clock_timestamp();
    update public.planner_state set json = jsonb_set(d, array['todos', i::text, 'done'], to_jsonb(k % 2 = 1))::text, saved_at = saved_at + 1000 where id = 'main';
    perform pg_temp.commit_triggers();
    if k > 1 then with_ms := with_ms || extract(epoch from clock_timestamp() - t0) * 1000; end if;   -- the first warms up
  end loop;
  execute 'alter table public.planner_state disable trigger adapter_mirror';
  for k in 1 .. 4 loop
    t0 := clock_timestamp();
    update public.planner_state set json = jsonb_set(d, array['todos', i::text, 'done'], to_jsonb(k % 2 = 1))::text, saved_at = saved_at + 1000 where id = 'main';
    perform pg_temp.commit_triggers();
    if k > 1 then without_ms := without_ms || extract(epoch from clock_timestamp() - t0) * 1000; end if;
  end loop;
  execute 'alter table public.planner_state enable trigger adapter_mirror';
  added := (select min(x) from unnest(with_ms) x) - (select min(x) from unnest(without_ms) x);
  insert into t_said values (0, format('speed on the copy (best of 3): a planner save takes %s ms with the trigger, %s ms without: %s ms added',
    round((select min(x) from unnest(with_ms) x)), round((select min(x) from unnest(without_ms) x), 1), round(added)));
  assert added < 300, format('the trigger adds %s ms to a planner save, more than the 300 ms allowed', round(added));
end
$test$;

-- ---------------------------------------------------------------- 6. access
do $test$
begin
  assert not has_table_privilege('anon', 'public.job_runs', 'select') and not has_table_privilege('anon', 'public.adapter_check_days', 'select'),
    'signed out, job_runs or adapter_check_days can be read';
  assert has_table_privilege('authenticated', 'public.job_runs', 'select')
     and not has_table_privilege('authenticated', 'public.job_runs', 'insert')
     and not has_table_privilege('authenticated', 'public.job_runs', 'update')
     and not has_table_privilege('authenticated', 'public.job_runs', 'delete'), 'authenticated can write job_runs, or can''t read it';
  assert (select relrowsecurity from pg_class where oid = 'public.job_runs'::regclass), 'job_runs has no RLS';
  assert (select coalesce('security_invoker=true' = any (c.reloptions), false) from pg_class c where c.oid = 'public.adapter_check_days'::regclass),
    'adapter_check_days isn''t security_invoker';
  assert not has_function_privilege('anon', 'public.adapter_clean_days(bigint, timestamptz)', 'execute'), 'signed out, adapter_clean_days() can be called';
end
$test$;
do $$ begin perform set_config('request.jwt.claims',
  '{"sub": "00000000-0000-4000-8000-0000000000e2", "email": "side-by-side-other@example.com", "role": "authenticated"}', true); end $$;
set local role authenticated;
do $test$
declare refused boolean := false;
begin
  assert (select count(*) from public.job_runs) = 0 and (select count(*) from public.adapter_check_days) = 0,
    'an account that isn''t staff reads job_runs';
  begin perform public.adapter_clean_days(); exception when insufficient_privilege then refused := true; end;
  assert refused, 'an account that isn''t staff could call adapter_clean_days()';
end
$test$;
reset role;
do $$ begin perform set_config('request.jwt.claims',
  '{"sub": "00000000-0000-4000-8000-0000000000e1", "email": "side-by-side-staff@example.com", "role": "authenticated"}', true); end $$;
set local role authenticated;
do $test$
begin
  assert (select count(*) from public.job_runs) > 0, 'staff can''t read job_runs';
  perform public.adapter_clean_days();
end
$test$;
reset role;

-- ---------------------------------------------------------------- what was checked, in four lines
do $test$
begin
  raise notice '%', (select line from t_said where part = 0);
  raise notice '%', (select string_agg(line, '; ' order by part) from t_said where part between 1 and 3);
  raise notice '%', (select string_agg(line, '; ' order by part) from t_said where part between 4 and 6);
  raise notice '%; access: job_runs and adapter_check_days read by staff only, written by nobody signed in, adapter_clean_days() staff only',
    (select line from t_said where part = 7);
end
$test$;

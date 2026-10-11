-- Loads saves merge instead of replacing the month (the fix of 9 Oct 2026, migration 20261009120000).
-- Run by database/rehearse.sh on the copy of last night's backup, after the new migrations, inside a transaction that
-- is rolled back. A failed check stops with an error that says which.
-- Since the switch-over (#13, pull request 9) planner_loads is frozen and save_loads() merges into the tables instead
-- (database/tests/switch_over_test.sql checks the same merges there). This test lifts the freeze first, as a rollback
-- does (private.unfreeze_planner_state()), and checks that save_loads() and the capture still merge into planner_loads
-- then, as before.

insert into public.planner_users (email) values ('rehearsal@example.com') on conflict do nothing;
do $$ begin perform set_config('request.jwt.claims', '{"email": "rehearsal@example.com", "role": "authenticated"}', true); end $$;

do $test$
declare r jsonb; j jsonb; saved bigint; before bigint; refused boolean; al bigint; mon text := to_char(current_date, 'YYYY-MM');
begin
  if private.planner_frozen_since('public.planner_loads'::regclass) is not null then perform private.unfreeze_planner_state(); end if;
  -- A month with two captured days, as the capture writes them, plus the marker older browser saves left behind.
  delete from public.planner_loads where month = '2099-01';
  insert into public.planner_loads (month, json, saved_at) values ('2099-01',
    '{"2099-01-01": {"done": true, "f": {"Ryanair|1001": 88, "Ryanair|1002": 91}, "source": "capture"},
      "2099-01-02": {"done": true, "f": {"Ryanair|1003": 77}, "source": "capture"}, "__savedAt": 5}', 5);

  -- 1. A whole-day entry (Check → load report) replaces that day's flights only.
  r := public.save_loads('2099-01', '{"2099-01-02": {"f": {"Ryanair|1003": 60}, "done": true, "savedAt": 10}}');
  j := r->'json';
  assert j #>> '{2099-01-01,f,Ryanair|1001}' = '88', 'a whole-day save changed another day';
  assert j #>> '{2099-01-02,f,Ryanair|1003}' = '60', 'a whole-day save did not set the day';
  assert j #>> '{2099-01-02,source}' = 'capture', 'a whole-day save dropped the day''s other fields';
  assert not (j ? '__savedAt'), 'the browser-only marker was kept in the document';
  select saved_at, json::jsonb into saved, j from public.planner_loads where month = '2099-01';
  assert saved > 5 and saved = (r->>'saved_at')::bigint, 'saved_at did not move on with the save';
  assert j = r->'json', 'the month returned is not the month stored';

  -- 2. Pasted loads set and clear single flights, and keep the rest of the day.
  r := public.save_loads('2099-01', '{"2099-01-01": {"set": {"Ryanair|1004": 70}, "del": ["Ryanair|1002"]}}');
  j := r->'json';
  assert j #>> '{2099-01-01,f,Ryanair|1001}' = '88', 'a pasted save dropped a flight it did not touch';
  assert j #>> '{2099-01-01,f,Ryanair|1004}' = '70', 'a pasted save did not set the flight';
  assert not (j #> '{2099-01-01,f}' ? 'Ryanair|1002'), 'a pasted save did not clear the flight';
  assert j #>> '{2099-01-01,done}' = 'true', 'a pasted save changed whether the day is complete';
  assert j #>> '{2099-01-02,f,Ryanair|1003}' = '60', 'a pasted save changed another day';

  -- 3. A month that doesn't exist yet is created.
  delete from public.planner_loads where month = '2099-02';
  r := public.save_loads('2099-02', '{"2099-02-03": {"set": {"Pan American|10": 50}, "done": true}}');
  assert (select json::jsonb #>> '{2099-02-03,f,Pan American|10}' from public.planner_loads where month = '2099-02') = '50',
    'a save to a new month was not stored';

  -- 4. Bad input is refused.
  begin perform public.save_loads('2099-01', '{"2099-02-01": {"f": {}}}'); refused := false; exception when others then refused := true; end;
  assert refused, 'a day outside the month was accepted';
  begin perform public.save_loads('January', '{}'); refused := false; exception when others then refused := true; end;
  assert refused, 'a month that is not YYYY-MM was accepted';

  -- 5. The capture moves saved_at on (the bug) and keeps what is already in the day. Since #13's pull request 3 the
  --    loads step reads game_flights, for an airline of ours: a test airline with one captured flight.
  select saved_at into before from public.planner_loads where month = mon;
  insert into public.airlines (world_id, group_id, game_id, planner_name, iata_code)
  select g.world_id, g.id, 999901, 'Rehearsal Air', 'RH'
    from public.groups g join public.worlds w on w.id = g.world_id and w.is_default
   where g.kind = 'ours' order by g.id limit 1
  returning id into al;
  insert into public.game_flights (world_id, airline_id, game_date, flight_no, dep_local, eco_pct, loads_captured_at)
  select a.world_id, a.id, current_date, 9001, '10:00', 55, now() from public.airlines a where a.id = al;
  r := private.apply_loads_from_capture(al);
  select saved_at, json::jsonb into saved, j from public.planner_loads where month = mon;
  assert saved > coalesce(before, 0), 'the capture did not move the month''s saved_at on';
  assert j #>> array[current_date::text, 'f', 'Rehearsal Air|9001'] = '55', 'the capture did not add its flight';

  -- 6. Only planner staff can save, and browsers can't write the month directly.
  perform set_config('request.jwt.claims', '{"email": "someone-else@example.com", "role": "authenticated"}', true);
  begin perform public.save_loads('2099-01', '{}'); refused := false; exception when others then refused := true; end;
  assert refused, 'someone who is not planner staff could save loads';
  assert not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'planner_loads' and cmd in ('INSERT', 'UPDATE', 'ALL')),
    'browsers can still write planner_loads directly';
  assert not has_function_privilege('anon', 'public.save_loads(text, jsonb)', 'execute'), 'save_loads is open to anyone';

  raise notice 'loads merge: all checks passed';
end
$test$;

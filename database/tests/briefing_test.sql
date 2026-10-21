-- The airline briefing's export kind (decision #24; spec docs/specs/2026-10-15-airline-briefing.md):
-- export_for_report(secret, 'briefing', '{"airline": ...}') and its builder, private.briefing_doc(). Run by
-- database/rehearse.sh on the copy of last night's backup, after the new migrations, inside a transaction that is rolled
-- back. A failed check stops with an error that says where (ids, keys and counts, never rows).
--   1. Who may call it: the builder is internal (nobody outside the database may call it), stable, with an empty search
--      path, and described; export_for_report() still runs as owner with an empty search path, signed out with the
--      ingest secret, and its description names the kind.
--   2. The secret required: signed out, a wrong secret is refused; p_arg without an airline, an airline that isn't one of
--      ours (a rival the scans saw) and one that doesn't exist are refused, saying why.
--   3. One airline only, for every one of our airlines on the copy: the same document by id, code and name (any case);
--      every delivery, plan card, to-do, fare change and loads row is that airline's (a to-do may be the group's), and
--      each part's count equals the tables' (aircraft on order or delivered; their plan cards and legs; open to-dos of the
--      airline and the group; fare changes not dropped; route_loads()'s routes and flights for it).
--   4. Hand-made rows (two test airports, a type, an aircraft on order with a card of two legs given out of order, to-dos
--      of two airlines, the group's, and one done): each lands in the right airline's document, in order, and nowhere
--      else; a done to-do and an active aircraft don't show.
--   5. Read only: the builder is stable, and calling the kind for every airline changes no row (the change log, the job
--      runs and every planner table's count stay as they were).

create temporary table t_br (k text primary key, v text) on commit drop;
insert into t_br values ('secret', 'briefing-test-' || gen_random_uuid()::text);
insert into public.ingest_secret (secret) select v from t_br where k = 'secret';
grant select on t_br to anon;

-- ---------------------------------------------------------------- 1. who may call it
do $test$
begin
  assert not exists (select 1 from pg_proc p cross join aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                      where p.oid = 'private.briefing_doc(bigint, timestamptz)'::regprocedure and a.grantee = 0),
    'everyone (PUBLIC) can call private.briefing_doc()';
  assert not has_function_privilege('anon', 'private.briefing_doc(bigint, timestamptz)', 'execute')
     and not has_function_privilege('authenticated', 'private.briefing_doc(bigint, timestamptz)', 'execute')
     and not has_function_privilege('service_role', 'private.briefing_doc(bigint, timestamptz)', 'execute'),
    'private.briefing_doc() can be called from outside the database';
  assert (select p.provolatile = 's' and coalesce('search_path=""' = any (p.proconfig), false) from pg_proc p
           where p.oid = 'private.briefing_doc(bigint, timestamptz)'::regprocedure),
    'private.briefing_doc() isn''t stable with an empty search path';
  assert obj_description('private.briefing_doc(bigint, timestamptz)'::regprocedure, 'pg_proc') is not null, 'private.briefing_doc() has no description';
  assert (select p.prosecdef and coalesce('search_path=""' = any (p.proconfig), false) from pg_proc p
           where p.oid = 'public.export_for_report(text, text, text)'::regprocedure),
    'export_for_report() doesn''t run as owner with an empty search path';
  assert has_function_privilege('anon', 'public.export_for_report(text, text, text)', 'execute'), 'signed out, export_for_report() can''t be called';
  assert obj_description('public.export_for_report(text, text, text)'::regprocedure, 'pg_proc') like '%kind briefing%',
    'export_for_report()''s description doesn''t mention kind briefing';
  raise notice 'who may call it: the builder is internal, stable, with an empty search path; export_for_report() as before; both described';
end
$test$;

-- ---------------------------------------------------------------- 2. the secret required, and the refusals (signed out, as the scripts call it)
set local role anon;
do $test$
declare s text := (select v from t_br where k = 'secret'); refused int := 0; bad text;
begin
  begin
    perform public.export_for_report('not-the-secret', 'briefing', '{"airline": 1}');
  exception when others then
    assert sqlerrm = 'not allowed', 'a wrong secret is refused for another reason: ' || sqlerrm;
    refused := refused + 1;
  end;
  assert refused = 1, 'kind briefing answers with a wrong secret';
  foreach bad in array array['', '{}', '[]', '{"airline": ""}', '{"airline": "no-such-airline"}', '{"airline": -1}'] loop
    begin
      perform public.export_for_report(s, 'briefing', bad);
      raise exception 'kind briefing answers for p_arg %', bad;
    exception when sqlstate '22023' then
      assert sqlerrm like 'briefing:%', 'kind briefing is refused for p_arg ' || bad || ' without saying why: ' || sqlerrm;
      refused := refused + 1;
    end;
  end loop;
  raise notice 'refused: a wrong secret, and % kinds of p_arg without one of our airlines', refused - 1;
end
$test$;
reset role;

-- a rival the scans saw (an airlines row outside our groups) is refused too
do $test$
declare s text := (select v from t_br where k = 'secret'); w bigint := private.fig_world(null); r bigint;
begin
  select a.id into r from public.airlines a where a.world_id = w and a.id not in (select al.airline_id from private.fig_airlines(w) al) order by a.id limit 1;
  if r is null then
    raise notice 'the copy has no airline outside ours: the rival refusal is left to the ids above';
    return;
  end if;
  begin
    perform public.export_for_report(s, 'briefing', jsonb_build_object('airline', r)::text);
    raise exception 'kind briefing answers for airline %, which isn''t one of ours', r;
  exception when sqlstate '22023' then
    null;
  end;
end
$test$;

-- ---------------------------------------------------------------- 5 (before). where the copy stands, to show nothing moved
create temporary view t_br_now as
  select 'change_log' as t, (select count(*) from public.change_log) as n, (select max(id)::text from public.change_log) as m
  union all select 'job_runs', (select count(*) from public.job_runs), (select max(id)::text from public.job_runs)
  union all select 'aircraft', (select count(*) from public.aircraft), (select max(updated_at)::text from public.aircraft)
  union all select 'plan_cards', (select count(*) from public.plan_cards), (select max(updated_at)::text from public.plan_cards)
  union all select 'plan_card_legs', (select count(*) from public.plan_card_legs), (select max(updated_at)::text from public.plan_card_legs)
  union all select 'todos', (select count(*) from public.todos), (select max(updated_at)::text from public.todos)
  union all select 'todo_items', (select count(*) from public.todo_items), (select max(updated_at)::text from public.todo_items)
  union all select 'fare_plan', (select count(*) from public.fare_plan), (select max(updated_at)::text from public.fare_plan);
create temporary table t_br_counts on commit drop as select * from t_br_now;

-- ---------------------------------------------------------------- 3. one airline only, every one of ours, against the tables
do $test$
declare
  s text := (select v from t_br where k = 'secret'); w bigint := private.fig_world(null); r record; d jsonb; rl jsonb;
  n_al int := 0; n_del int := 0; n_cards int := 0; n_legs int := 0; n_todos int := 0; n_fare int := 0; n_routes int := 0; n_levels int := 0; bad text;
  fl jsonb;
begin
  for r in select al.airline_id, al.iata_code, a.planner_name from private.fig_airlines(w) al join public.airlines a on a.id = al.airline_id order by al.ord loop
    n_al := n_al + 1;
    d := public.export_for_report(s, 'briefing', jsonb_build_object('airline', r.airline_id)::text);
    assert (d -> 'airline' ->> 'id')::bigint = r.airline_id, format('airline %s: the document is airline %s''s', r.airline_id, d -> 'airline' ->> 'id');
    assert d - 'as_of' - 'fare_plan' - 'route_loads'
           = public.export_for_report(s, 'briefing', jsonb_build_object('airline', lower(r.iata_code))::text) - 'as_of' - 'fare_plan' - 'route_loads',
      format('airline %s: by its code in lower case, another document', r.airline_id);
    if r.planner_name is not null then
      assert (public.export_for_report(s, 'briefing', jsonb_build_object('airline', upper(r.planner_name))::text) -> 'airline' ->> 'id')::bigint = r.airline_id,
        format('airline %s: by its planner name, another airline', r.airline_id);
    end if;
    -- deliveries: this airline's aircraft on order or delivered, every one, and no other
    select string_agg(x ->> 'aircraft_id', ', ') into bad from jsonb_array_elements(d -> 'deliveries') x
     where not exists (select 1 from public.aircraft a where a.id = (x ->> 'aircraft_id')::bigint and a.airline_id = r.airline_id
                          and a.status in ('on_order', 'delivered'));
    assert bad is null, format('airline %s: deliveries that aren''t its aircraft on order or delivered: %s', r.airline_id, bad);
    assert jsonb_array_length(d -> 'deliveries') = (select count(*) from public.aircraft a where a.airline_id = r.airline_id and a.status in ('on_order', 'delivered')),
      format('airline %s: %s deliveries, the table has %s', r.airline_id, jsonb_array_length(d -> 'deliveries'),
             (select count(*) from public.aircraft a where a.airline_id = r.airline_id and a.status in ('on_order', 'delivered')));
    n_del := n_del + jsonb_array_length(d -> 'deliveries');
    -- their plan cards and legs, as the tables hold them
    assert (select count(*) from jsonb_array_elements(d -> 'deliveries') x, jsonb_array_elements(x -> 'plan_cards') c)
         = (select count(*) from public.plan_cards c join public.aircraft a on a.id = c.aircraft_id
             where a.airline_id = r.airline_id and a.status in ('on_order', 'delivered')),
      format('airline %s: the deliveries'' plan cards differ from the table''s', r.airline_id);
    assert (select count(*) from jsonb_array_elements(d -> 'deliveries') x, jsonb_array_elements(x -> 'plan_cards') c, jsonb_array_elements(c -> 'legs') l)
         = (select count(*) from public.plan_card_legs l join public.plan_cards c on c.id = l.plan_card_id join public.aircraft a on a.id = c.aircraft_id
             where a.airline_id = r.airline_id and a.status in ('on_order', 'delivered')),
      format('airline %s: the plan cards'' legs differ from the table''s', r.airline_id);
    n_cards := n_cards + (select count(*) from jsonb_array_elements(d -> 'deliveries') x, jsonb_array_elements(x -> 'plan_cards') c);
    n_legs := n_legs + (select count(*) from jsonb_array_elements(d -> 'deliveries') x, jsonb_array_elements(x -> 'plan_cards') c, jsonb_array_elements(c -> 'legs') l);
    -- to-dos: open, the airline's or the group's
    select string_agg(x ->> 'id', ', ') into bad from jsonb_array_elements(d -> 'todos') x
     where not exists (select 1 from public.todos t where t.id = (x ->> 'id')::bigint and not t.done and (t.airline_id = r.airline_id or t.airline_id is null));
    assert bad is null, format('airline %s: to-dos that aren''t its open ones or the group''s: %s', r.airline_id, bad);
    assert jsonb_array_length(d -> 'todos') = (select count(*) from public.todos t where t.world_id = w and not t.done and (t.airline_id = r.airline_id or t.airline_id is null)),
      format('airline %s: the open to-dos differ from the table''s', r.airline_id);
    n_todos := n_todos + jsonb_array_length(d -> 'todos');
    -- the fare plan: this airline's, every change not dropped
    assert (d -> 'fare_plan' ->> 'airline_id')::bigint = r.airline_id, format('airline %s: the fare plan is another airline''s', r.airline_id);
    assert jsonb_array_length(d -> 'fare_plan' -> 'plan') = (select count(*) from public.fare_plan f where f.airline_id = r.airline_id and f.status <> 'dropped'),
      format('airline %s: the fare plan''s changes differ from the table''s', r.airline_id);
    n_fare := n_fare + jsonb_array_length(d -> 'fare_plan' -> 'plan');
    -- the fare levels (since 21 Oct; spec docs/specs/2026-10-21-frequencies-and-fares.md §2): fare_ladder()'s routes and
    -- cabins, each with its level, new level and whether this week's move is on the fare plan, and the launch level
    fl := private.fig_fare_ladder(r.airline_id, (d ->> 'as_of')::timestamptz);
    assert d -> 'fare_ladder' -> 'routes' = coalesce((select jsonb_agg(jsonb_build_object('route_id', e -> 'route_id', 'hub', e -> 'hub', 'dest', e -> 'dest',
                                                                                          'cabin', e -> 'cabin', 'level', e -> 'level', 'new_level', e -> 'new_level',
                                                                                          'planned', e -> 'planned') order by o)
                                                        from jsonb_array_elements(fl -> 'routes') with ordinality x(e, o)), '[]'::jsonb)
       and d #> '{fare_ladder,settings,launch_pct}' = fl #> '{settings,launch_pct}' and d -> 'fare_ladder' -> 'week_of' = fl -> 'week_of',
      format('airline %s: the fare levels differ from fare_ladder()''s', r.airline_id);
    n_levels := n_levels + jsonb_array_length(d -> 'fare_ladder' -> 'routes');
    -- the loads: route_loads()'s rows for this airline, every one and no other
    rl := private.fig_route_loads(w, (d ->> 'as_of')::timestamptz);
    assert not exists (select 1 from jsonb_array_elements(d -> 'route_loads' -> 'routes') x where (x ->> 'airline_id')::bigint <> r.airline_id)
       and not exists (select 1 from jsonb_array_elements(d -> 'route_loads' -> 'flights') x where (x ->> 'airline_id')::bigint <> r.airline_id),
      format('airline %s: loads of another airline', r.airline_id);
    assert d -> 'route_loads' -> 'routes' = coalesce((select jsonb_agg(x.v order by x.o) from jsonb_array_elements(rl -> 'routes') with ordinality x(v, o)
                                                        where (x.v ->> 'airline_id')::bigint = r.airline_id), '[]'::jsonb),
      format('airline %s: the loads by route differ from route_loads()''s', r.airline_id);
    n_routes := n_routes + jsonb_array_length(d -> 'route_loads' -> 'routes');
  end loop;
  assert n_al > 0, 'the copy has none of our airlines';
  raise notice 'one airline only, for % airlines: % deliveries, % plan cards, % legs, % open to-dos (the group''s in each), % fare changes, % routes'' and cabins'' fare levels (fare_ladder()''s), % routes'' loads, each as the tables hold them',
    n_al, n_del, n_cards, n_legs, n_todos, n_fare, n_levels, n_routes;
end
$test$;

-- ---------------------------------------------------------------- 5. read only: nothing moved
do $test$
declare bad text;
begin
  assert (select p.provolatile = 's' from pg_proc p where p.oid = 'private.briefing_doc(bigint, timestamptz)'::regprocedure), 'the builder isn''t stable';
  select string_agg(b.t, ', ') into bad
    from t_br_counts b join t_br_now a on a.t = b.t
   where (a.n, a.m) is distinct from (b.n, b.m);
  assert bad is null, 'calling kind briefing changed rows in: ' || bad;
  raise notice 'read only: the builder is stable, and the change log, job runs and planner tables are as they were';
end
$test$;

-- ---------------------------------------------------------------- 4. hand-made rows land in the right airline's document
do $test$
declare
  s text := (select v from t_br where k = 'secret'); w bigint := private.fig_world(null);
  a1 bigint; a2 bigint; t_id bigint; ac bigint; ac_active bigint; pc bigint; td1 bigint; td2 bigint; td_group bigint; td_done bigint;
  d1 jsonb; d2 jsonb; x jsonb;
begin
  select al.airline_id into a1 from private.fig_airlines(w) al order by al.ord limit 1;
  select al.airline_id into a2 from private.fig_airlines(w) al where al.airline_id <> a1 order by al.ord limit 1;
  assert a1 is not null and a2 is not null, 'the copy needs two of our airlines for this check';
  perform set_config('equinox.actor', 'script', true), set_config('equinox.actor_detail', 'briefing_test', true);
  insert into public.airports (code, city) values ('ZZA', 'Test A'), ('ZZB', 'Test B') on conflict (code) do nothing;
  insert into public.aircraft_types (world_id, name) values (w, 'BRIEFING TEST TYPE') returning id into t_id;
  insert into public.aircraft (world_id, airline_id, registration, aircraft_type_id, status, ordered_on, delivery_at, order_base_code, order_note)
  values (w, a1, 'ZZ-BRF1', t_id, 'on_order', current_date, now() + interval '3 days', 'ZZA', 'briefing test') returning id into ac;
  insert into public.aircraft (world_id, airline_id, registration, aircraft_type_id, status, base_code)
  values (w, a1, 'ZZ-BRF2', t_id, 'active', 'ZZA') returning id into ac_active;
  insert into public.plan_cards (world_id, airline_id, aircraft_id, base_code, title) values (w, a1, ac, 'ZZA', 'ZZA + ZZB') returning id into pc;
  -- given out of order: the document gives them by position
  insert into public.plan_card_legs (world_id, plan_card_id, position, flight_no, origin_code, dest_code, days_utc, dep_utc_min, block_min, service_code)
  values (w, pc, 2, 9902, 'ZZB', 'ZZA', '{1,3,5}', 600, 95, 'S1'), (w, pc, 1, 9901, 'ZZA', 'ZZB', '{1,3,5}', 420, 95, 'S1');
  insert into public.todos (world_id, airline_id, title, due_on) values (w, a1, 'briefing test: the first airline''s', current_date + 2) returning id into td1;
  insert into public.todo_items (world_id, todo_id, position, body) values (w, td1, 2, 'second step'), (w, td1, 1, 'first step');
  insert into public.todos (world_id, airline_id, title) values (w, a2, 'briefing test: the second airline''s') returning id into td2;
  insert into public.todos (world_id, airline_id, title) values (w, null, 'briefing test: the group''s') returning id into td_group;
  insert into public.todos (world_id, airline_id, title, done, done_at) values (w, a1, 'briefing test: done', true, now()) returning id into td_done;

  d1 := public.export_for_report(s, 'briefing', jsonb_build_object('airline', a1)::text);
  d2 := public.export_for_report(s, 'briefing', jsonb_build_object('airline', a2)::text);
  select v into x from jsonb_array_elements(d1 -> 'deliveries') v where (v ->> 'aircraft_id')::bigint = ac;
  assert x is not null, 'the aircraft on order isn''t in its airline''s deliveries';
  assert x ->> 'registration' = 'ZZ-BRF1' and x ->> 'type' = 'BRIEFING TEST TYPE' and x ->> 'status' = 'on_order'
     and x ->> 'order_base_code' = 'ZZA' and (x ->> 'arrived')::boolean = false and x ->> 'order_note' = 'briefing test',
    'the delivery''s fields read back wrong: ' || (x - 'plan_cards')::text;
  assert jsonb_array_length(x -> 'plan_cards') = 1 and x -> 'plan_cards' -> 0 ->> 'title' = 'ZZA + ZZB', 'its plan card isn''t there';
  assert (select jsonb_agg(l ->> 'flight_no') from jsonb_array_elements(x -> 'plan_cards' -> 0 -> 'legs') l) = '["9901", "9902"]'::jsonb,
    'the card''s legs aren''t in position order: ' || (x -> 'plan_cards' -> 0 -> 'legs')::text;
  assert x -> 'plan_cards' -> 0 -> 'legs' -> 0 = jsonb_build_object('position', 1, 'flight_no', 9901, 'origin_code', 'ZZA', 'dest_code', 'ZZB',
                                                                     'days_utc', '[1, 3, 5]'::jsonb, 'dep_utc_min', 420, 'block_min', 95, 'service_code', 'S1'),
    'the first leg reads back wrong: ' || (x -> 'plan_cards' -> 0 -> 'legs' -> 0)::text;
  assert not exists (select 1 from jsonb_array_elements(d1 -> 'deliveries') v where (v ->> 'aircraft_id')::bigint = ac_active),
    'an aircraft in service is among the deliveries';
  assert not exists (select 1 from jsonb_array_elements(d2 -> 'deliveries') v where (v ->> 'aircraft_id')::bigint = ac),
    'the first airline''s aircraft on order is in the second airline''s deliveries';
  -- to-dos: each airline its own and the group's; the done one nowhere
  assert exists (select 1 from jsonb_array_elements(d1 -> 'todos') v where (v ->> 'id')::bigint = td1 and v -> 'steps' = '["first step", "second step"]'::jsonb
                                                                       and (v ->> 'group')::boolean = false),
    'the first airline''s to-do isn''t in its document with its steps in order';
  assert exists (select 1 from jsonb_array_elements(d1 -> 'todos') v where (v ->> 'id')::bigint = td_group and (v ->> 'group')::boolean)
     and exists (select 1 from jsonb_array_elements(d2 -> 'todos') v where (v ->> 'id')::bigint = td_group and (v ->> 'group')::boolean),
    'the group''s to-do isn''t in both airlines'' documents, marked as the group''s';
  assert exists (select 1 from jsonb_array_elements(d2 -> 'todos') v where (v ->> 'id')::bigint = td2)
     and not exists (select 1 from jsonb_array_elements(d1 -> 'todos') v where (v ->> 'id')::bigint = td2)
     and not exists (select 1 from jsonb_array_elements(d2 -> 'todos') v where (v ->> 'id')::bigint = td1),
    'an airline''s to-do shows in the other airline''s document';
  assert not exists (select 1 from jsonb_array_elements(d1 -> 'todos') v where (v ->> 'id')::bigint = td_done), 'a done to-do is among the open ones';
  -- as of a moment after its delivery, the aircraft has arrived
  assert (select (v ->> 'arrived')::boolean from jsonb_array_elements(public.export_for_report(s, 'briefing',
            jsonb_build_object('airline', a1, 'as_of', now() + interval '4 days')::text) -> 'deliveries') v where (v ->> 'aircraft_id')::bigint = ac),
    'as of a moment after its delivery, the aircraft hasn''t arrived';
  raise notice 'hand-made rows: an aircraft on order with a card of 2 legs, 4 to-dos (two airlines, the group, one done), each in the right document';
end
$test$;

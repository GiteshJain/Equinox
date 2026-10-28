-- Lines in the planner (spec docs/specs/2026-10-27-long-haul-lines.md §2; build pull request 2 of 4,
-- 20261028180000_plan_lines.sql). Run by database/rehearse.sh on the copy of last night's backup, after the new
-- migrations, inside a transaction that is rolled back. A failed check stops with an error that says where (ids,
-- registrations made for the test and counts, never rows).
--   1. The catalogue: plan_lines and plan_line_legs with RLS on and one staff rule per action, nothing for anon,
--      authenticated reading and writing (manual §1: a new table grants its own access), updated_at and the change log
--      by trigger, a description on each table and every column, and plan_cards.line_id and line_day_offset described;
--      private.plan_line_slot() closed to everyone, with an empty search path, not running as owner, described.
--   2. As staff, through planner_save(): a line and its two legs in one call (the legs taking the line's new id), then
--      a card on the line at offset 0 and its legs in another, as Tails' Write the next card makes it; each read back,
--      every row logged as actor planner with the tab's ID.
--   3. One card per line and offset among aircraft that aren't retired: a second card at offset 0 is refused, through
--      planner_save() writing nothing, and as plain SQL; once the first aircraft is retired another can take offset 0;
--      bringing the first back from retired is then refused. Another offset is fine.
--   4. The tables' own checks: an offset of 7, a line without an offset, a line day of 8, a departure of 1440 and two
--      legs at one position are refused; a line with cards can't be deleted; a line without cards is deleted with its
--      legs, each logged.

create temporary table t_pl (k text primary key, v jsonb) on commit drop;
grant select, insert, update on t_pl to authenticated, anon;
insert into public.planner_users (email) values ('plan-lines-staff@example.com') on conflict do nothing;

-- ---------------------------------------------------------------- 1. the catalogue
do $test$
declare bad text; t text;
begin
  foreach t in array array['plan_lines', 'plan_line_legs'] loop
    assert to_regclass('public.' || t) is not null, t || ' is missing';
    assert (select c.relrowsecurity from pg_class c where c.oid = ('public.' || t)::regclass), 'RLS is off on ' || t;
    assert (select string_agg(lower(p.cmd), ',' order by p.cmd) from pg_policies p where p.schemaname = 'public' and p.tablename = t)
           = 'delete,insert,select,update', t || ' hasn''t one rule per action';
    select string_agg(p.policyname, ', ') into bad from pg_policies p
     where p.schemaname = 'public' and p.tablename = t
       and (p.roles <> '{authenticated}'
            or (p.cmd <> 'INSERT' and p.qual is distinct from '( SELECT is_planner_user() AS is_planner_user)')
            or (p.cmd in ('INSERT', 'UPDATE') and p.with_check is distinct from '( SELECT is_planner_user() AS is_planner_user)'));
    assert bad is null, t || ': rules that aren''t the staff check: ' || bad;
    select string_agg(x.p, ', ') into bad from unnest(array['select', 'insert', 'update', 'delete', 'truncate', 'references', 'trigger']) as x(p)
     where has_table_privilege('anon', 'public.' || t, x.p);
    assert bad is null, 'anon has ' || bad || ' on ' || t;
    select string_agg(x.p, ', ') into bad from unnest(array['select', 'insert', 'update', 'delete']) as x(p)
     where not has_table_privilege('authenticated', 'public.' || t, x.p);
    assert bad is null, 'authenticated lacks ' || bad || ' on ' || t;
    select string_agg(x.p, ', ') into bad from unnest(array['truncate', 'references', 'trigger']) as x(p)
     where has_table_privilege('authenticated', 'public.' || t, x.p);
    assert bad is null, 'authenticated has ' || bad || ' on ' || t;
    select string_agg(x.g, ', ') into bad from unnest(array['set_updated_at', 'log_change']) as x(g)
     where not exists (select 1 from pg_trigger g where g.tgrelid = ('public.' || t)::regclass and g.tgname = x.g and not g.tgisinternal);
    assert bad is null, t || ' lacks the trigger(s) ' || bad;
    assert obj_description(('public.' || t)::regclass, 'pg_class') is not null, t || ' has no description';
    select string_agg(a.attname, ', ') into bad from pg_attribute a
     where a.attrelid = ('public.' || t)::regclass and a.attnum > 0 and not a.attisdropped
       and a.attname not in ('id', 'world_id', 'created_at', 'updated_at') and col_description(a.attrelid, a.attnum) is null;
    assert bad is null, t || ': columns without a description: ' || bad;
  end loop;
  select string_agg(x.c, ', ') into bad from unnest(array['line_id', 'line_day_offset']) as x(c)
   where col_description('public.plan_cards'::regclass, (select a.attnum from pg_attribute a where a.attrelid = 'public.plan_cards'::regclass and a.attname = x.c)) is null;
  assert bad is null, 'plan_cards columns without a description: ' || bad;
  assert exists (select 1 from pg_trigger g where g.tgrelid = 'public.plan_cards'::regclass and g.tgname = 'plan_line_slot'), 'plan_cards has no plan_line_slot trigger';
  assert exists (select 1 from pg_trigger g where g.tgrelid = 'public.aircraft'::regclass and g.tgname = 'plan_line_slot'), 'aircraft has no plan_line_slot trigger';
  assert (select not p.prosecdef and coalesce('search_path=""' = any (p.proconfig), false) from pg_proc p where p.oid = 'private.plan_line_slot()'::regprocedure),
    'private.plan_line_slot() runs as owner or has a search path';
  assert not has_function_privilege('anon', 'private.plan_line_slot()', 'execute') and not has_function_privilege('authenticated', 'private.plan_line_slot()', 'execute')
     and not exists (select 1 from pg_proc p cross join aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where p.oid = 'private.plan_line_slot()'::regprocedure and a.grantee = 0),
    'private.plan_line_slot() can be called from outside';
  assert obj_description('private.plan_line_slot()'::regprocedure, 'pg_proc') is not null, 'private.plan_line_slot() has no description';
  raise notice 'catalogue: plan_lines and plan_line_legs staff-only with RLS, triggers and descriptions; plan_cards'' line columns described; the slot trigger closed';
end
$test$;

-- rules_input() carries each type's reach (range_km), so optimise-line needs no --range; the document read once, into a
-- variable, before it is compared with the table
do $test$
declare d jsonb; bad text; n int;
begin
  d := private.rules_input_doc(null, 'flown');
  select count(*), string_agg(e ->> 'name', ', ') filter (where not e ? 'range_km'
           or (e ->> 'range_km')::int is distinct from (select t.range_km from public.aircraft_types t where t.id = (e ->> 'id')::bigint))
    into n, bad from jsonb_array_elements(d -> 'aircraft_types') e;
  assert bad is null, 'rules_input()''s types without their range_km: ' || bad;
  raise notice 'rules_input(): all % types carry range_km as the table has it', n;
end
$test$;

-- the test's rows: an airline of ours (else the first), a type, two airports and three aircraft on order, made as Claude
do $test$
declare w bigint := (select x.id from public.worlds x where x.is_default); al bigint; ty bigint; a1 text; a2 text; n int; v_id bigint; r text;
begin
  assert w is not null, 'the copy has no default world';
  select x.id into al from public.airlines x left join public.groups g on g.id = x.group_id and g.world_id = x.world_id
   where x.world_id = w order by (g.kind = 'ours') desc nulls last, x.position nulls last, x.id limit 1;
  select t.id into ty from public.aircraft_types t where t.world_id = w order by t.id limit 1;
  select min(code), max(code) into a1, a2 from (select p.code from public.airports p order by p.code limit 2) x;
  assert al is not null and ty is not null and a1 is distinct from a2, 'the copy has no airline, type or two airports';
  insert into t_pl values ('world', to_jsonb(w)), ('airline', to_jsonb(al)), ('type', to_jsonb(ty)), ('a1', to_jsonb(a1)), ('a2', to_jsonb(a2));
  perform set_config('equinox.actor', 'claude', true), set_config('equinox.actor_detail', 'plan_lines test', true);
  for n in 1..3 loop
    r := 'ZZPL' || n || substr(md5(random()::text), 1, 4);
    insert into public.aircraft (world_id, airline_id, registration, aircraft_type_id, status, acquired)
    values (w, al, r, ty, 'on_order', 'new') returning id into v_id;
    insert into t_pl values ('ac' || n, to_jsonb(v_id)), ('reg' || n, to_jsonb(r));
  end loop;
  perform set_config('equinox.actor', '', true), set_config('equinox.actor_detail', '', true);
end
$test$;

-- ---------------------------------------------------------------- 2. staff, through planner_save()
do $$ begin perform set_config('request.jwt.claims',
  '{"sub": "00000000-0000-4000-8000-0000000000d1", "email": "plan-lines-staff@example.com", "role": "authenticated"}', true); end $$;
set local role authenticated;
do $test$
declare
  w bigint := (select (v #>> '{}')::bigint from t_pl where k = 'world');
  al bigint := (select (v #>> '{}')::bigint from t_pl where k = 'airline');
  ty bigint := (select (v #>> '{}')::bigint from t_pl where k = 'type');
  a1 text := (select v #>> '{}' from t_pl where k = 'a1');
  a2 text := (select v #>> '{}' from t_pl where k = 'a2');
  ac1 bigint := (select (v #>> '{}')::bigint from t_pl where k = 'ac1');
  r jsonb; v_line bigint; v_card bigint; v_mark bigint; n int; bad text;
begin
  assert public.is_planner_user(), 'the test account isn''t staff';
  select coalesce(max(id), 0) into v_mark from public.change_log;
  -- a line and its two legs, in one call
  r := public.planner_save(jsonb_build_array(
    jsonb_build_object('table', 'plan_lines', 'op', 'insert', 'as', 'line', 'values', jsonb_build_object(
      'world_id', w, 'airline_id', al, 'aircraft_type_id', ty, 'name', 'plan_lines test line', 'optimiser_answer', '{"search": {"finished": true}}'::jsonb)),
    jsonb_build_object('table', 'plan_line_legs', 'op', 'insert', 'from', '{"line_id": "line"}'::jsonb, 'values', jsonb_build_object(
      'world_id', w, 'position', 1, 'line_day', 1, 'flight_no', 9001, 'origin_code', a1, 'dest_code', a2, 'dep_utc_min', 600, 'block_min', 480, 'service_code', 'S5')),
    jsonb_build_object('table', 'plan_line_legs', 'op', 'insert', 'from', '{"line_id": "line"}'::jsonb, 'values', jsonb_build_object(
      'world_id', w, 'position', 2, 'line_day', 2, 'flight_no', 9002, 'origin_code', a2, 'dest_code', a1, 'dep_utc_min', 120, 'block_min', 500, 'service_code', 'S5'))),
    'tab-plan-lines');
  assert (r ->> 'ok')::boolean, 'planner_save() refused a line and its legs: ' || r::text;
  assert jsonb_array_length(r -> 'rows') = 3, 'planner_save() answered with ' || jsonb_array_length(r -> 'rows') || ' rows, expected 3';
  v_line := (r #>> '{rows,0,key,id}')::bigint;
  assert (select count(*) from public.plan_line_legs l where l.line_id = v_line) = 2, 'the line''s two legs weren''t written with its id';
  assert (select l.name = 'plan_lines test line' and l.optimiser_answer #>> '{search,finished}' = 'true' from public.plan_lines l where l.id = v_line), 'the line doesn''t read back';
  insert into t_pl values ('line', to_jsonb(v_line));
  -- a card on the line at offset 0, and its legs on their weekdays (offset 0: line day d on weekday d)
  r := public.planner_save(jsonb_build_array(
    jsonb_build_object('table', 'plan_cards', 'op', 'insert', 'as', 'card', 'values', jsonb_build_object(
      'world_id', w, 'airline_id', al, 'aircraft_id', ac1, 'base_code', a1, 'title', 'plan_lines test line · 1 of 7', 'line_id', v_line, 'line_day_offset', 0)),
    jsonb_build_object('table', 'plan_card_legs', 'op', 'insert', 'from', '{"plan_card_id": "card"}'::jsonb, 'values', jsonb_build_object(
      'world_id', w, 'position', 1, 'flight_no', 9001, 'origin_code', a1, 'dest_code', a2, 'days_utc', '{1}'::smallint[], 'dep_utc_min', 600, 'block_min', 480, 'service_code', 'S5')),
    jsonb_build_object('table', 'plan_card_legs', 'op', 'insert', 'from', '{"plan_card_id": "card"}'::jsonb, 'values', jsonb_build_object(
      'world_id', w, 'position', 2, 'flight_no', 9002, 'origin_code', a2, 'dest_code', a1, 'days_utc', '{2}'::smallint[], 'dep_utc_min', 120, 'block_min', 500, 'service_code', 'S5'))),
    'tab-plan-lines');
  assert (r ->> 'ok')::boolean, 'planner_save() refused a card on the line: ' || r::text;
  v_card := (r #>> '{rows,0,key,id}')::bigint;
  assert (select c.line_id = v_line and c.line_day_offset = 0 from public.plan_cards c where c.id = v_card), 'the card doesn''t read back on its line';
  insert into t_pl values ('card', to_jsonb(v_card));
  -- every row logged as planner with the tab
  select count(*), string_agg(distinct l.actor || '/' || coalesce(l.actor_detail, ''), ', ') into n, bad from public.change_log l
   where l.id > v_mark and l.table_name in ('plan_lines', 'plan_line_legs', 'plan_cards', 'plan_card_legs');
  assert n = 6, format('the change log has %s rows for the two saves, expected 6', n);
  assert bad = 'planner/tab-plan-lines', 'the change log names ' || bad || ', not planner with the tab';
  assert (select count(*) from public.change_log l where l.id > v_mark and l.table_name = 'plan_line_legs' and l.op = 'insert'
            and (l.new_values ->> 'line_id')::bigint = v_line) = 2, 'the legs'' rows in the change log don''t carry the line';
  raise notice 'planner_save(): a line with 2 legs, then a card at offset 0 with 2 legs, each read back; 6 change-log rows as planner with the tab';
end
$test$;

-- ---------------------------------------------------------------- 3. one card per line and offset
do $test$
declare
  w bigint := (select (v #>> '{}')::bigint from t_pl where k = 'world');
  al bigint := (select (v #>> '{}')::bigint from t_pl where k = 'airline');
  v_line bigint := (select (v #>> '{}')::bigint from t_pl where k = 'line');
  ac1 bigint := (select (v #>> '{}')::bigint from t_pl where k = 'ac1');
  ac2 bigint := (select (v #>> '{}')::bigint from t_pl where k = 'ac2');
  ac3 bigint := (select (v #>> '{}')::bigint from t_pl where k = 'ac3');
  refused boolean; v_n bigint; v_at timestamptz; v_card2 bigint;
begin
  -- through planner_save(): refused, and nothing written (not even the call's other row)
  select count(*) into v_n from public.plan_cards c where c.line_id = v_line;
  refused := false;
  begin
    perform public.planner_save(jsonb_build_array(
      jsonb_build_object('table', 'todos', 'op', 'insert', 'values', jsonb_build_object('world_id', w, 'title', 'plan_lines test: must not stay')),
      jsonb_build_object('table', 'plan_cards', 'op', 'insert', 'values', jsonb_build_object(
        'world_id', w, 'airline_id', al, 'aircraft_id', ac2, 'line_id', v_line, 'line_day_offset', 0))), 'tab-plan-lines');
  exception when unique_violation then refused := true;
  end;
  assert refused, 'planner_save() let a second card take offset 0 of the line';
  assert (select count(*) from public.plan_cards c where c.line_id = v_line) = v_n, 'a refused card was written';
  assert not exists (select 1 from public.todos t where t.title = 'plan_lines test: must not stay'), 'the refused call''s other row was written';
  -- as plain SQL too
  refused := false;
  begin
    insert into public.plan_cards (world_id, airline_id, aircraft_id, line_id, line_day_offset) values (w, al, ac2, v_line, 0);
  exception when unique_violation then refused := true;
  end;
  assert refused, 'plain SQL let a second card take offset 0 of the line';
  -- another offset is fine
  insert into public.plan_cards (world_id, airline_id, aircraft_id, line_id, line_day_offset) values (w, al, ac2, v_line, 1) returning id into v_card2;
  -- moving it onto a taken offset is refused
  refused := false;
  begin
    update public.plan_cards set line_day_offset = 0 where id = v_card2;
  exception when unique_violation then refused := true;
  end;
  assert refused, 'a card could be moved onto a taken offset';
  -- the first aircraft retired: its card stays, and frees the place
  select a.updated_at into v_at from public.aircraft a where a.id = ac1;
  update public.aircraft set status = 'retired', retired_on = current_date where id = ac1;
  insert into public.plan_cards (world_id, airline_id, aircraft_id, line_id, line_day_offset) values (w, al, ac3, v_line, 0);
  assert (select count(*) from public.plan_cards c where c.line_id = v_line and c.line_day_offset = 0) = 2, 'the retired aircraft''s card didn''t stay';
  -- and can't come back from retired while its place is taken
  refused := false;
  begin
    update public.aircraft set status = 'active', retired_on = null where id = ac1;
  exception when unique_violation then refused := true;
  end;
  assert refused, 'an aircraft came back from retired onto a taken place';
  raise notice 'one card per line and offset: a second card refused (planner_save() writing nothing, and plain SQL), moving onto a taken offset refused, a retired aircraft''s place taken by another, its return refused';
end
$test$;

-- ---------------------------------------------------------------- 4. the tables' own checks, and removing a line
do $test$
declare
  w bigint := (select (v #>> '{}')::bigint from t_pl where k = 'world');
  al bigint := (select (v #>> '{}')::bigint from t_pl where k = 'airline');
  ty bigint := (select (v #>> '{}')::bigint from t_pl where k = 'type');
  a1 text := (select v #>> '{}' from t_pl where k = 'a1');
  a2 text := (select v #>> '{}' from t_pl where k = 'a2');
  v_line bigint := (select (v #>> '{}')::bigint from t_pl where k = 'line');
  v_card bigint := (select (v #>> '{}')::bigint from t_pl where k = 'card');
  v_other bigint; v_mark bigint; refused int := 0; n int;
begin
  begin update public.plan_cards set line_day_offset = 7 where id = v_card; exception when check_violation then refused := refused + 1; end;
  begin update public.plan_cards set line_day_offset = null where id = v_card; exception when check_violation then refused := refused + 1; end;
  begin insert into public.plan_line_legs (world_id, line_id, position, line_day, origin_code, dest_code, dep_utc_min) values (w, v_line, 9, 8, a1, a2, 0);
  exception when check_violation then refused := refused + 1; end;
  begin insert into public.plan_line_legs (world_id, line_id, position, line_day, origin_code, dest_code, dep_utc_min) values (w, v_line, 9, 1, a1, a2, 1440);
  exception when check_violation then refused := refused + 1; end;
  begin insert into public.plan_line_legs (world_id, line_id, position, line_day, origin_code, dest_code, dep_utc_min) values (w, v_line, 1, 3, a1, a2, 0);
  exception when unique_violation then refused := refused + 1; end;
  assert refused = 5, format('%s of 5 bad rows were refused (offset 7, line without offset, line day 8, departure 1440, a position twice)', refused);
  -- a line with cards stays
  refused := 0;
  begin delete from public.plan_lines where id = v_line; exception when foreign_key_violation then refused := 1; end;
  assert refused = 1, 'a line with cards could be deleted';
  -- a line without cards goes with its legs, each logged
  insert into public.plan_lines (world_id, airline_id, aircraft_type_id, name) values (w, al, ty, 'plan_lines test line 2') returning id into v_other;
  insert into public.plan_line_legs (world_id, line_id, position, line_day, origin_code, dest_code, dep_utc_min) values (w, v_other, 1, 1, a1, a2, 60), (w, v_other, 2, 1, a2, a1, 900);
  select coalesce(max(id), 0) into v_mark from public.change_log;
  delete from public.plan_lines where id = v_other;
  assert not exists (select 1 from public.plan_line_legs l where l.line_id = v_other), 'the line''s legs stayed';
  select count(*) into n from public.change_log l where l.id > v_mark and l.op = 'delete' and l.table_name in ('plan_lines', 'plan_line_legs');
  assert n = 3, format('removing a line logged %s rows, expected 3 (the line and its 2 legs)', n);
  -- a name is the airline's once
  refused := 0;
  begin insert into public.plan_lines (world_id, airline_id, aircraft_type_id, name) values (w, al, ty, 'plan_lines test line');
  exception when unique_violation then refused := 1; end;
  assert refused = 1, 'two lines of one airline could share a name';
  raise notice 'the tables'' checks refuse 5 bad rows and a name twice; a line with cards stays; one without goes with its legs, 3 rows logged';
end
$test$;
reset role;

do $$ begin raise notice 'plan lines: all checks passed'; end $$;

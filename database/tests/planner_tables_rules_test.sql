-- The planner tables' rules (#13 build pull request 2; design §3, §4 and §9 step 1).
-- Run by database/rehearse.sh on the copy of last night's backup, after the new migrations, inside a transaction that
-- is rolled back. A failed check stops with an error that says which.
--   1. The reference rows: one world marked default (Gander), one group of ours, six airlines with distinct game IDs and
--      codes.
--   2. As staff: design §4's worked example (Kingfisher's DEL-JFK pair) stored in UTC reads back in flight_legs_local
--      exactly as the game shows it; flight_no_clashes lists a real clash and not a number repeated on other days.
--   3. flight_legs refuses bad weekdays, times and a leg whose airports don't match its route in its direction, and a
--      route or rotation change that would break that; plan_card_legs refuses bad weekdays too.
--   4. A row can't point into another world (#14), the enumerated columns refuse other values, and every foreign key
--      has an index.
-- The test makes its own airline and airports (codes no real airport has), so it works whatever data the copy holds.

-- ---------------------------------------------------------------- 1. reference rows
do $test$
declare w bigint; g bigint; n int; bad text;
begin
  select count(*) into n from public.worlds where is_default;
  assert n = 1, format('%s worlds are marked default, expected 1', n);
  select id into w from public.worlds where is_default and name = 'Gander' and game_host = 'gander.airlinesim.aero' and kind = 'exclusive';
  assert w is not null, 'the default world isn''t Gander (gander.airlinesim.aero, exclusive)';
  select count(*) into n from public.groups where world_id = w and kind = 'ours';
  assert n = 1, format('Gander has %s groups of ours, expected 1', n);
  select id into g from public.groups where world_id = w and kind = 'ours' and name = 'equinox.';
  assert g is not null, 'our group in Gander isn''t equinox.';
  select count(*) into n from public.airlines where group_id = g;
  assert n = 6, format('equinox. has %s airlines, expected 6', n);
  assert (select count(distinct game_id) = 6 and count(distinct iata_code) = 6 and count(distinct planner_name) = 6
                 and count(distinct position) = 6 and bool_and(active)
            from public.airlines where group_id = g), 'our six airlines don''t have distinct game IDs, codes, names and places';
  select string_agg(planner_name || ' ' || game_id || ' ' || iata_code || ' ' || home_airport_code, ', ' order by game_id) into bad
    from public.airlines where group_id = g;
  assert bad = 'Ryanair 112 FR CDG, Kingfisher 113 KF DEL, Pan American 114 AW JFK, Virgin Atlantic 203 VS LGW, China Eastern 208 MU PVG, Malaysia Airlines 210 MH KUL',
    'our airlines'' game IDs, codes or home airports changed: ' || bad;
  assert (select is_lcc from public.airlines where group_id = g and iata_code = 'FR')
     and not exists (select 1 from public.airlines where group_id = g and is_lcc and iata_code <> 'FR'), 'Ryanair isn''t our only LCC';
end
$test$;

-- ---------------------------------------------------------------- 2. as staff: the worked example and clashes
insert into public.planner_users (email) values ('rules-staff@example.com') on conflict do nothing;
create temporary table t_rules_ids (k text primary key, v bigint) on commit drop;
grant select, insert on t_rules_ids to authenticated;
do $$ begin perform set_config('request.jwt.claims',
  '{"sub": "00000000-0000-4000-8000-0000000000b1", "email": "rules-staff@example.com", "role": "authenticated"}', true); end $$;
set local role authenticated;
do $test$
declare w bigint; al bigint; ro bigint; rot bigint; rot2 bigint; l1 bigint; l2 bigint; l3 bigint; v record; n int;
begin
  select id into w from public.worlds where name = 'Gander';
  -- airports standing in for Delhi (UTC+5:30) and New York JFK (UTC-5), and a third
  insert into public.airports (code, city, utc_offset) values ('XDEL', 'Test Delhi', 5.5), ('XJFK', 'Test New York', -5), ('XOTH', 'Test other', 0);
  insert into public.airlines (world_id, game_id, planner_name, iata_code) values (w, 999001, 'Rules Test Air', 'KF') returning id into al;
  insert into public.routes (world_id, airline_id, hub_code, dest_code, source) values (w, al, 'XDEL', 'XJFK', 'research') returning id into ro;
  insert into public.rotations (world_id, airline_id, route_id, legacy_key, service_code, fare_pct) values (w, al, ro, 'rules-z5qbaeg', 'S3', 100) returning id into rot;
  -- design §4: out Mon, Wed, Fri 01:30 local -> 04:19 local the same day; back Mon, Wed, Fri 07:30 -> 07:19 the next day
  insert into public.flight_legs (world_id, airline_id, rotation_id, leg_no, flight_no, origin_code, dest_code, days_utc, dep_utc_min, block_min)
  values (w, al, rot, 1, 1001, 'XDEL', 'XJFK', '{2,4,7}', 1200, 799) returning id into l1;
  insert into public.flight_legs (world_id, airline_id, rotation_id, leg_no, flight_no, origin_code, dest_code, days_utc, dep_utc_min, block_min)
  values (w, al, rot, 2, 1002, 'XJFK', 'XDEL', '{1,3,5}', 750, 799) returning id into l2;
  insert into t_rules_ids values ('world', w), ('airline', al), ('route', ro), ('rotation', rot), ('leg1', l1), ('leg2', l2);

  select * into v from public.flight_legs_local where id = l1;
  assert v.flight_code = 'KF 1001', 'leg 1''s flight code is ' || v.flight_code;
  assert v.dep_local = '01:30' and v.dep_local_min = 90 and v.days_local = '{1,3,5}',
    format('leg 1 departs %s on %s locally, expected 01:30 on {1,3,5}', v.dep_local, v.days_local);
  assert v.arr_local = '04:19' and v.arr_local_day_offset = 0, format('leg 1 arrives %s (+%s) locally, expected 04:19 the same day', v.arr_local, v.arr_local_day_offset);
  assert v.arr_utc_min = 559 and v.arr_utc_day_offset = 1, format('leg 1 arrives %s (+%s) UTC, expected 09:19 the next day', v.arr_utc_min, v.arr_utc_day_offset);
  select * into v from public.flight_legs_local where id = l2;
  assert v.dep_local = '07:30' and v.days_local = '{1,3,5}', format('leg 2 departs %s on %s locally, expected 07:30 on {1,3,5}', v.dep_local, v.days_local);
  assert v.arr_local = '07:19' and v.arr_local_day_offset = 1, format('leg 2 arrives %s (+%s) locally, expected 07:19 the next day', v.arr_local, v.arr_local_day_offset);
  assert v.arr_utc_min = 109 and v.arr_utc_day_offset = 1, format('leg 2 arrives %s (+%s) UTC, expected 01:49 the next day', v.arr_utc_min, v.arr_utc_day_offset);

  -- the same number on other days (another aircraft, Tue/Thu/Sat locally) is no clash; on a shared day it is
  insert into public.rotations (world_id, airline_id, route_id, legacy_key) values (w, al, ro, 'rules-second') returning id into rot2;
  insert into public.flight_legs (world_id, airline_id, rotation_id, leg_no, flight_no, origin_code, dest_code, days_utc, dep_utc_min, block_min)
  values (w, al, rot2, 1, 1001, 'XDEL', 'XJFK', '{1,3,5}', 1200, 799) returning id into l3;
  select count(*) into n from public.flight_no_clashes where airline_id = al;
  assert n = 0, format('a number flown on other days shows %s clash(es)', n);
  update public.flight_legs set days_utc = '{1,3,4}' where id = l3;   -- now also Fri locally, like leg 1
  select * into v from public.flight_no_clashes where airline_id = al;
  assert v.flight_no = 1001 and v.weekday = 5 and v.legs = 2 and v.leg_ids = array[l1, l3]
     and (select count(*) from public.flight_no_clashes where airline_id = al) = 1,
    'flight_no_clashes doesn''t list the Friday clash of 1001';
  insert into t_rules_ids values ('rotation2', rot2), ('leg3', l3);
end
$test$;

-- ---------------------------------------------------------------- 3. refusals
do $test$
declare w bigint := (select v from t_rules_ids where k = 'world'); al bigint := (select v from t_rules_ids where k = 'airline');
  ro bigint := (select v from t_rules_ids where k = 'route'); rot bigint := (select v from t_rules_ids where k = 'rotation');
  l1 bigint := (select v from t_rules_ids where k = 'leg1'); l2 bigint := (select v from t_rules_ids where k = 'leg2');
  ro2 bigint; ac bigint; pc bigint; bad text; refused boolean; d text;
begin
  -- weekdays: sorted, no repeats, 1 to 7, at least one
  foreach d in array array['{}', '{0}', '{8}', '{3,1}', '{1,1}', '{1,NULL}', '{1,2,3,4,5,6,7,7}', '[0:1]={1,2}'] loop
    refused := false;
    begin update public.flight_legs set days_utc = d::smallint[] where id = l1;
    exception when check_violation then refused := true; end;
    assert refused, 'flight_legs took the weekdays ' || d;
  end loop;
  refused := false;
  begin update public.flight_legs set days_utc = null where id = l1; exception when not_null_violation then refused := true; end;
  assert refused, 'flight_legs took no weekdays';
  -- departure minute 0 to 1439
  foreach d in array array['-1', '1440'] loop
    refused := false;
    begin update public.flight_legs set dep_utc_min = d::smallint where id = l1; exception when check_violation then refused := true; end;
    assert refused, 'flight_legs took the departure minute ' || d;
  end loop;
  update public.flight_legs set dep_utc_min = 0 where id = l1;
  update public.flight_legs set dep_utc_min = 1439 where id = l1;
  update public.flight_legs set dep_utc_min = 1200 where id = l1;
  -- airports must match the route in the leg's direction
  refused := false;
  begin update public.flight_legs set origin_code = 'XJFK', dest_code = 'XDEL' where id = l1; exception when check_violation then refused := true; end;
  assert refused, 'leg 1 took the return direction';
  refused := false;
  begin update public.flight_legs set origin_code = 'XDEL', dest_code = 'XJFK' where id = l2; exception when check_violation then refused := true; end;
  assert refused, 'leg 2 took the outbound direction';
  refused := false;
  begin update public.flight_legs set dest_code = 'XOTH' where id = l1; exception when check_violation then refused := true; end;
  assert refused, 'leg 1 took an airport its route doesn''t fly to';
  refused := false;
  begin update public.flight_legs set leg_no = 3 where id = l1; exception when check_violation then refused := true; end;
  assert refused, 'flight_legs took leg number 3';
  -- ... and a route or rotation change can't break that
  refused := false;
  begin update public.routes set dest_code = 'XOTH' where id = ro; exception when check_violation then refused := true; end;
  assert refused, 'a route''s destination changed under its legs';
  insert into public.routes (world_id, airline_id, hub_code, dest_code, source) values (w, al, 'XDEL', 'XOTH', 'added') returning id into ro2;
  refused := false;
  begin update public.rotations set route_id = ro2 where id = rot; exception when check_violation then refused := true; end;
  assert refused, 'a rotation moved to another route under its legs';

  -- plan-card legs follow the same weekday rule, every day by default
  insert into public.aircraft (world_id, airline_id, registration, status) values (w, al, 'RULES-001', 'on_order') returning id into ac;
  insert into public.plan_cards (world_id, airline_id, aircraft_id, title) values (w, al, ac, 'Rules test') returning id into pc;
  insert into public.plan_card_legs (world_id, plan_card_id, position, origin_code, dest_code) values (w, pc, 1, 'XDEL', 'XOTH');
  assert (select days_utc from public.plan_card_legs where plan_card_id = pc) = '{1,2,3,4,5,6,7}', 'a plan-card leg isn''t every day by default';
  refused := false;
  begin update public.plan_card_legs set days_utc = '{7,1}' where plan_card_id = pc; exception when check_violation then refused := true; end;
  assert refused, 'plan_card_legs took unsorted weekdays';

  -- enumerated columns take only their values
  refused := false;
  begin update public.aircraft set status = 'flying' where id = ac; exception when check_violation then refused := true; end;
  assert refused, 'aircraft took the status flying';
  refused := false;
  begin insert into public.growth_log (world_id, airline_id, logged_on, move) values (w, al, current_date, 'huge'); exception when check_violation then refused := true; end;
  assert refused, 'growth_log took the move huge';
  refused := false;
  begin insert into public.worlds (name, game_host, kind, is_default) values ('Rules test world', 'rules.example', 'exclusive', true);
  exception when unique_violation then refused := true; end;
  assert refused, 'a second world was marked default';
end
$test$;

-- ---------------------------------------------------------------- 4. worlds kept apart, and indexes
do $test$
declare w bigint := (select v from t_rules_ids where k = 'world'); al bigint := (select v from t_rules_ids where k = 'airline');
  ro bigint := (select v from t_rules_ids where k = 'route'); w2 bigint; al2 bigint; refused boolean; bad text;
begin
  insert into public.worlds (name, game_host, kind) values ('Rules test world', 'rules.example', 'short_term') returning id into w2;
  insert into public.airlines (world_id, game_id, planner_name) values (w2, 999001, 'Rules Test Air') returning id into al2;
  -- a rotation in the other world can't use this world's route, nor a route this world's airline
  refused := false;
  begin insert into public.rotations (world_id, airline_id, route_id) values (w2, al2, ro); exception when foreign_key_violation then refused := true; end;
  assert refused, 'a rotation pointed at a route in another world';
  refused := false;
  begin insert into public.routes (world_id, airline_id, hub_code, dest_code, source) values (w2, al, 'XJFK', 'XDEL', 'research');
  exception when foreign_key_violation then refused := true; end;
  assert refused, 'a route pointed at an airline in another world';
  -- a leg can't point at another airline's rotation
  refused := false;
  begin insert into public.flight_legs (world_id, airline_id, rotation_id, leg_no, origin_code, dest_code, days_utc)
        values (w2, al2, (select v from t_rules_ids where k = 'rotation2'), 2, 'XJFK', 'XDEL', '{1}');
  exception when foreign_key_violation then refused := true; end;
  assert refused, 'a leg pointed at another airline''s rotation';
end
$test$;
reset role;

do $test$
declare bad text;
begin
  -- every foreign key on a new table has an index that starts with one of its columns (design §2)
  select string_agg(c.conrelid::regclass::text || ' (' || c.conname || ')', ', ') into bad
    from pg_constraint c
   where c.contype = 'f'
     and c.conrelid in (select oid from pg_class where relnamespace = 'public'::regnamespace and relname = any (array[
       'worlds', 'groups', 'airlines', 'airline_bases', 'airline_aircraft_types', 'countries', 'airports', 'world_airports',
       'aircraft_types', 'cabin_configs', 'aircraft', 'aircraft_cabin_keeps', 'markets', 'service_profiles', 'routes',
       'rotations', 'flight_legs', 'plan_cards', 'plan_card_legs', 'todos', 'todo_items', 'growth_log', 'spending_log',
       'fare_plan', 'interline_agreements', 'monthly_checks', 'dismissals', 'cash_entries', 'load_entries', 'load_days',
       'settings', 'world_rules', 'airline_order_cabins', 'change_log']))
     and not exists (select 1 from pg_index i where i.indrelid = c.conrelid and i.indkey[0] = any (c.conkey));
  assert bad is null, 'foreign keys without an index: ' || bad;
end
$test$;

do $$ begin raise notice 'planner tables rules: all checks passed'; end $$;

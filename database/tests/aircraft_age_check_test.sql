-- The aircraft age check and replacement warning (migration 20261022090000_aircraft_age_check.sql; spec
-- docs/specs/2026-10-22-aircraft-age-check.md §1; manual §3, replacement by age). Run by database/rehearse.sh on the copy
-- of last night's backup, after the new migrations, inside a transaction that is rolled back. A failed check stops with
-- an error that says which (codes, registrations and counts only).
--   1. The objects: aircraft.acquired text, not null, no default (since 26 Oct: a row added without it is refused), only
--      new or used, described; the three used aircraft
--      bought on 22 Oct (N023AW, 9M-AAY, G-AAFB; ids 283, 284, 285) marked used, every other aircraft from before the build new; the settings
--      replace_new_years 3, replace_used_years 10 and replace_warn_days 60 in every world, world rows only, each with its
--      unit, description, since 22 Oct and reason.
--   2. On the copy, at its latest fleet night (when it has one): fleet_checks() now, and every aircraft row with acquired
--      and replace_at_years; then one new aircraft's latest age set to 2.9 gives replace ("replace at 3 years (now 2.9):
--      order its replacement"), at 3.1 the past-age words; one marked used at 9.9 gives replace at 10; one new aircraft
--      delivered a month before the night with age 3.6 gives age ("looks used (3.6 years in the game), marked new").
--   3. A world of its own, made inside the test, with its fleet night written straight into game_fleet: new at 2.8 isn't
--      warned and at 2.9 is; new at 3.0 is past its age; used at 9.8 isn't warned, at 9.9 is, at 10.0 is past; a used one
--      older in the game than its time with us is no age problem; a new one 3.6 in the game a month after delivery is
--      (and past its age); one without a delivery date is never an age problem; 0.2 years exactly isn't over the line;
--      an aircraft the planner doesn't have gets neither; worst first, after the other kinds, with their words and counts;
--      an airline's own replace_warn_days is not read (world rows only); each aircraft row carries acquired and
--      replace_at_years.
--   4. As staff: aircraft.acquired read, and changed through planner_save() (the planner's saves still pass), logged as
--      the tab; a third value refused. fleet_checks() as staff gives what postgres gets.

create temporary table t_ag (k text primary key, v jsonb) on commit drop;
grant select, insert, update on t_ag to authenticated, anon;
insert into public.planner_users (email) values ('age-check-staff@example.com') on conflict do nothing;

-- ---------------------------------------------------------------- 1. the objects
do $test$
declare c record; n_worlds int := (select count(*) from public.worlds); bad text;
begin
  select a.attnotnull, format_type(a.atttypid, a.atttypmod) as type, pg_get_expr(d.adbin, d.adrelid) as def,
         col_description(a.attrelid, a.attnum) as descr
    into c
    from pg_attribute a left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
   where a.attrelid = 'public.aircraft'::regclass and a.attname = 'acquired' and not a.attisdropped;
  assert c.type = 'text' and c.attnotnull and c.def is null, 'aircraft.acquired isn''t text, not null, with no default: ' || coalesce(c.type, 'missing') || ' ' || coalesce(c.def, '');
  assert c.descr like 'How the aircraft came%used%manual §3%no default%', 'aircraft.acquired has no description';
  -- a row added without it is refused (since 26 Oct)
  begin
    insert into public.aircraft (world_id, airline_id, registration, status)
    select al.world_id, al.id, 'ZZ-NOACQ', 'on_order' from public.airlines al order by al.id limit 1;
    raise exception 'an aircraft without acquired was accepted';
  exception when not_null_violation then null;
  end;
  assert exists (select 1 from pg_constraint x where x.conrelid = 'public.aircraft'::regclass and x.conname = 'aircraft_acquired_kinds'
                    and x.contype = 'c' and pg_get_constraintdef(x.oid) like '%new%used%'),
    'aircraft.acquired isn''t checked to new or used';
  -- the three used aircraft of 22 Oct, by their ids (present on a copy from 22 Oct on)
  select string_agg(a.registration, ', ') into bad from public.aircraft a
   where a.id in (283, 284, 285) and a.registration in ('N023AW', '9M-AAY', 'G-AAFB') and a.acquired <> 'used';
  assert bad is null, 'not marked used: ' || bad;
  -- and no other aircraft from before the build is (one logged used later is Claude's, manual §3, the used market)
  select string_agg(a.registration, ', ') into bad from public.aircraft a
   where a.acquired = 'used' and a.created_at < timestamptz '2026-10-23 00:00+00'
     and not (a.id in (283, 284, 285) and a.registration in ('N023AW', '9M-AAY', 'G-AAFB'));
  assert bad is null, 'marked used, but not one of the three: ' || bad;
  assert (select count(*) from public.settings s
           where s.airline_id is null and s.since = date '2026-10-22' and s.reason = 'manual §3, replacement by age (Gitesh, 22 Oct)'
             and length(coalesce(s.description, '')) > 60
             and ((s.key = 'replace_new_years' and s.value = '3'::jsonb and s.unit = 'years')
               or (s.key = 'replace_used_years' and s.value = '10'::jsonb and s.unit = 'years')
               or (s.key = 'replace_warn_days' and s.value = '60'::jsonb and s.unit = 'days'))) = 3 * n_worlds,
    'replace_new_years 3, replace_used_years 10 and replace_warn_days 60 aren''t in every world, with unit, description, since and reason';
  assert not exists (select 1 from public.settings s where s.airline_id is not null
                        and s.key in ('replace_new_years', 'replace_used_years', 'replace_warn_days')),
    'an airline has its own replacement setting';
  assert obj_description('public.fleet_checks(bigint, timestamptz)'::regprocedure, 'pg_proc') like '%replace_at_years%looks used%',
    'fleet_checks()''s description doesn''t give replace and age';
  raise notice 'aircraft.acquired: text, not null, no default (a row without it refused), new or used only, described; % aircraft used (the three of 22 Oct), the rest new; the three settings in each of % world(s), described',
    (select count(*) from public.aircraft a where a.acquired = 'used'), n_worlds;
end
$test$;

-- ---------------------------------------------------------------- 2. on the copy
do $test$
declare w bigint := (select x.id from public.worlds x where x.is_default); d jsonb; night date; t timestamptz := now();
  n_new bigint; n_used bigint; n_age bigint; r_new text; r_used text; r_age text; x jsonb; got text;
begin
  perform set_config('equinox.actor', 'claude', true), set_config('equinox.actor_detail', 'aircraft age check test', true);
  d := private.fig_fleet_checks(w, t);
  night := (d ->> 'night')::date;
  if night is null then
    raise notice 'on the copy: no fleet night yet, so only the hand-made world below';
    return;
  end if;
  assert d -> 'counts' ? 'replace' and d -> 'counts' ? 'age', 'the counts have no replace or age: ' || (d -> 'counts')::text;
  assert not exists (select 1 from jsonb_array_elements(d -> 'airlines') al, jsonb_array_elements(al -> 'aircraft') a
                      where not (a ? 'acquired' and a ? 'replace_at_years')),
    'an aircraft row has no acquired or replace_at_years';
  assert not exists (select 1 from jsonb_array_elements(d -> 'airlines') al, jsonb_array_elements(al -> 'aircraft') a
                      where a ->> 'aircraft_id' is not null
                        and (a ->> 'replace_at_years')::numeric is distinct from case a ->> 'acquired' when 'used' then 10 else 3 end),
    'an aircraft''s replace_at_years isn''t 3 for new or 10 for used';
  raise notice 'on the copy, the night of %: % replace, % age, % problems in all (none expected on 22 Oct: the oldest aircraft is 0.1 years)',
    night, d #>> '{counts,replace}', d #>> '{counts,age}', d #>> '{counts,problems}';

  -- three aircraft of the night the planner has, marked new and with a delivery date
  select f.aircraft_id, f.registration into n_new, r_new from public.game_fleet f join public.aircraft a on a.id = f.aircraft_id
   where f.world_id = w and f.capture_day = night and a.acquired = 'new' order by f.registration limit 1;
  select f.aircraft_id, f.registration into n_used, r_used from public.game_fleet f join public.aircraft a on a.id = f.aircraft_id
   where f.world_id = w and f.capture_day = night and f.aircraft_id <> n_new order by a.acquired = 'used' desc, f.registration limit 1;
  select f.aircraft_id, f.registration into n_age, r_age from public.game_fleet f join public.aircraft a on a.id = f.aircraft_id
   where f.world_id = w and f.capture_day = night and f.aircraft_id not in (n_new, n_used) order by f.registration limit 1;
  if n_age is null then
    raise notice 'on the copy: fewer than three aircraft on the night, so only the hand-made world below';
    return;
  end if;
  update public.aircraft set acquired = 'new' where id in (n_new, n_age);
  update public.aircraft set acquired = 'used' where id = n_used;
  update public.aircraft set delivery_at = (night - 30)::timestamp at time zone 'UTC' where id = n_age;
  update public.game_fleet set age_years = 0.1 where world_id = w and capture_day = night and aircraft_id in (n_new, n_used, n_age);

  update public.game_fleet set age_years = 2.9 where world_id = w and capture_day = night and aircraft_id = n_new;
  update public.game_fleet set age_years = 9.9 where world_id = w and capture_day = night and aircraft_id = n_used;
  update public.game_fleet set age_years = 3.6 where world_id = w and capture_day = night and aircraft_id = n_age;
  d := private.fig_fleet_checks(w, t);
  select string_agg(k || ' ' || r, ', ') into got
    from (values ('replace', r_new), ('replace', r_used), ('replace', r_age), ('age', r_age)) v(k, r)
   where not exists (select 1 from jsonb_array_elements(d -> 'problems') p where p ->> 'kind' = v.k and p ->> 'registration' = v.r);
  assert got is null, 'on the copy these are missing from fleet_checks(): ' || got;
  select p into x from jsonb_array_elements(d -> 'problems') p where p ->> 'kind' = 'replace' and p ->> 'registration' = r_new;
  assert x ->> 'words' like r_new || ' (%): replace at 3 years (now 2.9): order its replacement', 'the copy''s 2.9: ' || coalesce(x ->> 'words', 'none');
  select p into x from jsonb_array_elements(d -> 'problems') p where p ->> 'kind' = 'replace' and p ->> 'registration' = r_used;
  assert x ->> 'words' like r_used || ' (%): replace at 10 years (now 9.9): order its replacement', 'the copy''s used 9.9: ' || coalesce(x ->> 'words', 'none');
  select p into x from jsonb_array_elements(d -> 'problems') p where p ->> 'kind' = 'age' and p ->> 'registration' = r_age;
  assert x ->> 'words' like r_age || ' (%): looks used (3.6 years in the game), marked new', 'the copy''s 3.6 a month after delivery: ' || coalesce(x ->> 'words', 'none');
  assert (x ->> 'aircraft_id')::bigint = n_age, 'the age problem doesn''t carry its aircraft';

  update public.game_fleet set age_years = 3.1 where world_id = w and capture_day = night and aircraft_id = n_new;
  d := private.fig_fleet_checks(w, t);
  select p into x from jsonb_array_elements(d -> 'problems') p where p ->> 'kind' = 'replace' and p ->> 'registration' = r_new;
  assert x ->> 'words' like r_new || ' (%): past its replacement age (3 years, now 3.1)', 'the copy''s 3.1: ' || coalesce(x ->> 'words', 'none');
  raise notice 'on the copy: % at 2.9 replace, at 3.1 past its age; % (used) at 9.9 replace at 10; % at 3.6 a month after delivery looks used', r_new, r_used, r_age;
  perform set_config('equinox.actor', '', true), set_config('equinox.actor_detail', '', true);
end
$test$;

-- ---------------------------------------------------------------- 3. a world of its own
do $setup$
declare w bigint; g bigint; aa bigint; ab bigint; ty bigint; c1 bigint; night date := date '2030-04-10';
  t timestamptz := timestamptz '2030-04-10 20:00+00'; r record;
begin
  perform set_config('equinox.actor', 'claude', true), set_config('equinox.actor_detail', 'aircraft age check test', true);
  insert into public.airports (code, utc_offset) values ('ZG1', 0.00), ('ZG2', 0.00) on conflict (code) do update set utc_offset = excluded.utc_offset;
  insert into public.worlds (name, game_host, kind) values ('aircraft age check test', 'age-check.test', 'exclusive') returning id into w;
  insert into public.settings (world_id, airline_id, key, value, unit, description)
  select w, null, s.key, s.value, s.unit, s.description from public.settings s
    join public.worlds x on x.id = s.world_id and x.is_default where s.airline_id is null;
  insert into public.settings (world_id, airline_id, key, value) values (w, null, 'maintenance_min_pct', '100'::jsonb) on conflict do nothing;
  insert into public.settings (world_id, airline_id, key, value) values (w, null, 'replace_new_years', '3'::jsonb), (w, null, 'replace_used_years', '10'::jsonb),
    (w, null, 'replace_warn_days', '60'::jsonb) on conflict on constraint settings_world_airline_key_key do update set value = excluded.value;
  insert into public.groups (world_id, name, kind) values (w, 'ours', 'ours') returning id into g;
  insert into public.airlines (world_id, group_id, game_id, planner_name, public_name, iata_code, home_airport_code, active, position)
  values (w, g, 990801, 'Age A', 'Age A', 'GA', 'ZG1', true, 1) returning id into aa;
  insert into public.airlines (world_id, group_id, game_id, planner_name, public_name, iata_code, home_airport_code, active, position)
  values (w, g, 990802, 'Age B', 'Age B', 'GB', 'ZG2', true, 2) returning id into ab;
  -- an airline's own warning window isn't read: the rule is the world's (spec §1, world rows, no airline overrides)
  insert into public.settings (world_id, airline_id, key, value) values (w, ab, 'replace_warn_days', '400'::jsonb);
  insert into public.aircraft_types (world_id, name) values (w, 'AGE TEST TYPE') returning id into ty;
  insert into public.cabin_configs (world_id, code, aircraft_type_id, cabin, seats, business_seats, economy_seats)
  values (w, 'AG-166', ty, 'Standard', 166, 16, 150) returning id into c1;
  -- registration, airline, acquired, days with us before the night (null: no delivery date), the game's age
  for r in select * from (values
      ('GA-001', aa, 'new', 1030, 2.8),    -- under the window: nothing
      ('GA-002', aa, 'new', 1060, 2.9),    -- in the window: replace
      ('GA-003', aa, 'new', 1100, 3.0),    -- past
      ('GA-004', aa, 'used', 30, 9.8),     -- used, under its window; older than its time with us, but used: no age
      ('GA-005', aa, 'used', 30, 9.9),     -- used, in the window
      ('GA-006', aa, 'used', 30, 10.0),    -- used, past
      ('GA-007', aa, 'new', 30, 3.6),      -- new, 3.6 a month after delivery: looks used, and past its age
      ('GA-008', aa, 'new', null, 3.6),    -- new, no delivery date: no age, still past its age
      ('GB-001', ab, 'new', 73, 0.4),      -- 0.4 - 73/365.25 = 0.2001: just over the line
      ('GB-002', ab, 'new', 37, 0.3),      -- 0.3 - 37/365.25 = 0.1987: not over it
      ('GB-003', ab, 'new', 700, 2.0)      -- the airline's own 400 days isn't read: nothing
    ) v(reg, al, acq, days, age) loop
    insert into public.aircraft (world_id, airline_id, registration, aircraft_type_id, cabin_config_id, status, base_code, acquired, delivery_at)
    values (w, r.al, r.reg, ty, c1, 'active', case when r.al = aa then 'ZG1' else 'ZG2' end, r.acq,
            case when r.days is not null then (night - r.days)::timestamp at time zone 'UTC' + interval '3 hours' end);
  end loop;
  -- the night's fleet pages, as the capture keeps them; GA-099 the planner doesn't have, 9.9 in the game
  insert into public.game_fleet (world_id, airline_id, capture_day, aircraft_id, registration, type_name, location_from, age_years,
                                 condition_pct, maintenance_pct, seats_y, seats_c, seats_f, pilots, owned, contract_status, fleet_name, captured_at)
  select w, a.airline_id, night, a.id, a.registration, 'Airbus A321NEO Light', a.base_code, v.age, 95, 120, 150, 16, 0, true, false, 'active', a.base_code, t
    from public.aircraft a join (values ('GA-001', 2.8), ('GA-002', 2.9), ('GA-003', 3.0), ('GA-004', 9.8), ('GA-005', 9.9), ('GA-006', 10.0),
                                        ('GA-007', 3.6), ('GA-008', 3.6), ('GB-001', 0.4), ('GB-002', 0.3), ('GB-003', 2.0)) v(reg, age)
                       on v.reg = a.registration
   where a.world_id = w;
  insert into public.game_fleet (world_id, airline_id, capture_day, aircraft_id, registration, type_name, location_from, age_years,
                                 condition_pct, maintenance_pct, seats_y, seats_c, seats_f, pilots, owned, contract_status, fleet_name, captured_at)
  values (w, aa, night, null, 'GA-099', 'Airbus A321NEO Light', 'ZG1', 9.9, 95, 120, 150, 16, 0, true, false, 'active', 'ZG1', t);
  insert into t_ag values ('w', to_jsonb(w)), ('aa', to_jsonb(aa)), ('t', to_jsonb(t + interval '1 hour'));
  perform set_config('equinox.actor', '', true), set_config('equinox.actor_detail', '', true);
end
$setup$;

do $test$
declare w bigint := (select (v #>> '{}')::bigint from t_ag where k = 'w'); t timestamptz := (select (v #>> '{}')::timestamptz from t_ag where k = 't');
  d jsonb; got text; want text; x jsonb;
begin
  d := private.fig_fleet_checks(w, t);
  assert d ->> 'night' = '2030-04-10', 'the night isn''t 10 April 2030: ' || coalesce(d ->> 'night', 'none');
  select string_agg((p ->> 'kind') || ' ' || (p ->> 'registration'), ', ' order by o) into got from jsonb_array_elements(d -> 'problems') with ordinality e(p, o);
  want := 'not_in_planner GA-099, replace GA-002, replace GA-003, replace GA-005, replace GA-006, replace GA-007, replace GA-008, age GA-007, age GB-001';
  assert got = want, format('the problems should be %s, worst first; got %s', want, coalesce(got, 'none'));
  select string_agg(p ->> 'words', ' | ' order by o) into got from jsonb_array_elements(d -> 'problems') with ordinality e(p, o)
   where p ->> 'kind' in ('replace', 'age');
  want := 'GA-002 (ZG1): replace at 3 years (now 2.9): order its replacement | GA-003 (ZG1): past its replacement age (3 years, now 3.0)'
       || ' | GA-005 (ZG1): replace at 10 years (now 9.9): order its replacement | GA-006 (ZG1): past its replacement age (10 years, now 10.0)'
       || ' | GA-007 (ZG1): past its replacement age (3 years, now 3.6) | GA-008 (ZG1): past its replacement age (3 years, now 3.6)'
       || ' | GA-007 (ZG1): looks used (3.6 years in the game), marked new | GB-001 (ZG2): looks used (0.4 years in the game), marked new';
  assert got = want, format('the words should be %s; got %s', want, got);
  assert d -> 'counts' = '{"maintenance": 0, "crew": 0, "cabin": 0, "not_in_planner": 1, "not_in_game": 0, "replace": 6, "age": 2, "problems": 9}'::jsonb,
    'the counts: ' || (d -> 'counts')::text;
  select p into x from jsonb_array_elements(d -> 'problems') p where p ->> 'kind' = 'age' and p ->> 'registration' = 'GA-007';
  assert x ->> 'code' = 'GA' and x ->> 'base' = 'ZG1' and (x ->> 'aircraft_id')::bigint = (select a.id from public.aircraft a where a.world_id = w and a.registration = 'GA-007'),
    'a problem doesn''t carry its airline, base and aircraft: ' || x::text;
  select a into x from jsonb_array_elements(d -> 'airlines') al, jsonb_array_elements(al -> 'aircraft') a where a ->> 'registration' = 'GA-007';
  assert x ->> 'acquired' = 'new' and (x ->> 'replace_at_years')::numeric = 3 and x -> 'problems' = '["replace", "age"]'::jsonb,
    'GA-007''s row: ' || x::text;
  select a into x from jsonb_array_elements(d -> 'airlines') al, jsonb_array_elements(al -> 'aircraft') a where a ->> 'registration' = 'GA-005';
  assert x ->> 'acquired' = 'used' and (x ->> 'replace_at_years')::numeric = 10 and x -> 'problems' = '["replace"]'::jsonb, 'GA-005''s row: ' || x::text;
  select a into x from jsonb_array_elements(d -> 'airlines') al, jsonb_array_elements(al -> 'aircraft') a where a ->> 'registration' = 'GA-099';
  assert x -> 'acquired' = 'null'::jsonb and x -> 'replace_at_years' = 'null'::jsonb, 'an aircraft the planner doesn''t have has an age rule: ' || x::text;
  -- the numbers are the settings': warned from 400 days, GA-001 at 2.8 is in the window too
  update public.settings set value = '400'::jsonb where world_id = w and airline_id is null and key = 'replace_warn_days';
  d := private.fig_fleet_checks(w, t);
  assert (d #>> '{counts,replace}')::int = 9, 'with replace_warn_days 400 every aircraft from 1.9 (new) or 8.9 (used) should be warned: ' || (d -> 'counts')::text;
  update public.settings set value = '60'::jsonb where world_id = w and airline_id is null and key = 'replace_warn_days';
  insert into t_ag values ('doc', private.fig_fleet_checks(w, t));
  raise notice 'a world of its own: new warned from 2.9 (60 days before 3), past at 3.0; used from 9.9, past at 10.0; the cross-check on new aircraft only, with a delivery date, over 0.2 years (0.2001 yes, 0.1987 no); none for an aircraft the planner lacks; after the other kinds, with words and counts; the window from the world''s setting only';
end
$test$;

-- ---------------------------------------------------------------- 4. as staff
do $$ begin perform set_config('request.jwt.claims',
  '{"sub": "00000000-0000-4000-8000-0000000000a9", "email": "age-check-staff@example.com", "role": "authenticated"}', true); end $$;
set local role authenticated;
do $test$
declare w bigint := (select (v #>> '{}')::bigint from t_ag where k = 'w'); t timestamptz := (select (v #>> '{}')::timestamptz from t_ag where k = 't');
  a record; r jsonb; refused boolean := false;
begin
  select x.id, x.acquired, x.updated_at into a from public.aircraft x where x.world_id = w and x.registration = 'GB-002';
  assert a.acquired = 'new', 'staff can''t read aircraft.acquired';
  -- as Claude logs a won auction (manual §3, the used market): the aircraft marked used, through planner_save()
  r := public.planner_save(jsonb_build_array(jsonb_build_object('table', 'aircraft', 'op', 'update', 'key', jsonb_build_object('id', a.id),
         'base', a.updated_at, 'values', jsonb_build_object('acquired', 'used'))), 'age-check-test');
  assert (r ->> 'ok')::boolean, 'planner_save() didn''t take aircraft.acquired: ' || r::text;
  select x.id, x.acquired, x.updated_at into a from public.aircraft x where x.world_id = w and x.registration = 'GB-002';
  assert a.acquired = 'used', 'aircraft.acquired wasn''t saved';
  begin
    r := public.planner_save(jsonb_build_array(jsonb_build_object('table', 'aircraft', 'op', 'update', 'key', jsonb_build_object('id', a.id),
           'base', a.updated_at, 'values', jsonb_build_object('acquired', 'leased'))), 'age-check-test');
    refused := not coalesce((r ->> 'ok')::boolean, false);
  exception when check_violation then refused := true;
  end;
  assert refused, 'aircraft.acquired took a third value';
  insert into t_ag values ('staff', public.fleet_checks(w, t));
end
$test$;
reset role;

do $test$
declare w bigint := (select (v #>> '{}')::bigint from t_ag where k = 'w'); t timestamptz := (select (v #>> '{}')::timestamptz from t_ag where k = 't');
  got text;
begin
  select string_agg(c.op || ' ' || c.actor, ', ') into got from public.change_log c
   where c.table_name = 'aircraft' and c.row_key ->> 'id' = (select a.id::text from public.aircraft a where a.world_id = w and a.registration = 'GB-002')
     and c.op = 'update';
  assert got = 'update planner', 'the save isn''t logged once as the planner: ' || coalesce(got, 'none');
  -- GB-002 now used: the doc staff got is the one postgres gets now
  assert (select v from t_ag where k = 'staff') = private.fig_fleet_checks(w, t), 'staff don''t get what postgres gets from fleet_checks()';
  raise notice 'as staff: aircraft.acquired read and marked used through planner_save(), logged as the planner, a third value refused; fleet_checks() as postgres gets it';
end
$test$;

do $$ begin raise notice 'aircraft age check: all checks passed'; end $$;

-- rules_input(): the planning library's input in one call (decision #19, build pull request 2; spec
-- docs/specs/2026-10-12-rules-library.md §2). Run by database/rehearse.sh on the copy of last night's backup, after the
-- new migrations, inside a transaction that is rolled back. A failed check stops with an error that says where (ids,
-- keys and counts, never rows).
--   1. Who may call it: authenticated only (signed out, nobody); runs as owner with an empty search path; described.
--      The internal builder, private.rules_input_doc(), is nobody's to call but postgres's, and described.
--   2. As postgres: the document's counts equal the tables' (settings, world rules, types, cabins, airports used,
--      airlines, bases, aircraft, routes not removed, rotations, legs).
--   3. One leg, one airport and one setting read back exactly.
--   4. An airline's override wins over the world value: in that airline's settings, while the world's stay as they are
--      for the document and for every other airline. Every override the copy already has reads back the same way.
--   5. Signed out, refused; an account that isn't staff, refused; staff get what postgres gets.
--   6. export_for_report(secret, 'rules'), signed out as the scripts call it, gives the same document (with and without
--      the world's id); a wrong secret is refused.

create temporary table t_ri (k text primary key, v jsonb) on commit drop;
grant select, insert, update on t_ri to authenticated, anon;
insert into public.planner_users (email) values ('rules-input-staff@example.com') on conflict do nothing;

-- ---------------------------------------------------------------- 1. who may call it
do $test$
begin
  assert (select p.prosecdef and coalesce('search_path=""' = any (p.proconfig), false) from pg_proc p
           where p.oid = 'public.rules_input(bigint)'::regprocedure),
    'rules_input() doesn''t run as owner with an empty search path';
  assert not has_function_privilege('anon', 'public.rules_input(bigint)', 'execute'), 'signed out, rules_input() can be called';
  assert has_function_privilege('authenticated', 'public.rules_input(bigint)', 'execute'), 'signed in, rules_input() can''t be called';
  assert not exists (select 1 from pg_proc p cross join aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                      where p.oid in ('public.rules_input(bigint)'::regprocedure, 'private.rules_input_doc(bigint)'::regprocedure) and a.grantee = 0),
    'everyone (PUBLIC) can call rules_input() or private.rules_input_doc()';
  assert not has_function_privilege('anon', 'private.rules_input_doc(bigint)', 'execute')
     and not has_function_privilege('authenticated', 'private.rules_input_doc(bigint)', 'execute'),
    'private.rules_input_doc() can be called from outside the database';
  assert (select coalesce('search_path=""' = any (p.proconfig), false) from pg_proc p where p.oid = 'private.rules_input_doc(bigint)'::regprocedure),
    'private.rules_input_doc() doesn''t have an empty search path';
  assert obj_description('public.rules_input(bigint)'::regprocedure, 'pg_proc') is not null, 'rules_input() has no description';
  assert obj_description('private.rules_input_doc(bigint)'::regprocedure, 'pg_proc') is not null, 'private.rules_input_doc() has no description';
  assert obj_description('public.export_for_report(text, text, text)'::regprocedure, 'pg_proc') like '%rules_input()%',
    'export_for_report()''s description doesn''t mention kind rules';
  raise notice 'who may call it: signed in only, runs as owner with an empty search path; its builder is internal; both described';
end
$test$;

-- ---------------------------------------------------------------- 2. the document's counts equal the tables'
do $test$
declare
  w bigint := (select x.id from public.worlds x where x.is_default);
  d jsonb;
  n_air int; n_ap int;
begin
  assert w is not null, 'the copy has no default world';
  d := public.rules_input();
  insert into t_ri values ('world', to_jsonb(w)), ('doc', d);
  assert (d #>> '{world,id}')::bigint = w, 'the document isn''t the default world''s';
  assert public.rules_input(w) = d, 'rules_input(the default world''s id) differs from rules_input()';
  assert (select count(*) from jsonb_object_keys(d -> 'settings')) = (select count(*) from public.settings s where s.world_id = w and s.airline_id is null),
    'settings: the document''s count differs from the table''s';
  assert (select count(*) from jsonb_object_keys(d -> 'world_rules')) = (select count(*) from public.world_rules r where r.world_id = w),
    'world_rules: the document''s count differs from the table''s';
  assert jsonb_array_length(d -> 'aircraft_types') = (select count(*) from public.aircraft_types t where t.world_id = w), 'aircraft_types: counts differ';
  assert jsonb_array_length(d -> 'cabin_configs') = (select count(*) from public.cabin_configs c where c.world_id = w), 'cabin_configs: counts differ';
  assert jsonb_array_length(d -> 'airline_bases') = (select count(*) from public.airline_bases b where b.world_id = w), 'airline_bases: counts differ';
  assert jsonb_array_length(d -> 'aircraft') = (select count(*) from public.aircraft a where a.world_id = w), 'aircraft: counts differ';
  assert jsonb_array_length(d -> 'routes') = (select count(*) from public.routes r where r.world_id = w and not r.removed), 'routes (not removed): counts differ';
  assert jsonb_array_length(d -> 'rotations') = (select count(*) from public.rotations r where r.world_id = w), 'rotations: counts differ';
  assert jsonb_array_length(d -> 'flight_legs') = (select count(*) from public.flight_legs l where l.world_id = w), 'flight_legs: counts differ';
  select count(*) into n_ap from (
    select r.hub_code as c from public.routes r where r.world_id = w and not r.removed
    union select r.dest_code from public.routes r where r.world_id = w and not r.removed
    union select l.origin_code from public.flight_legs l where l.world_id = w
    union select l.dest_code from public.flight_legs l where l.world_id = w
    union select b.airport_code from public.airline_bases b where b.world_id = w
    union select a.base_code from public.aircraft a where a.world_id = w and a.base_code is not null) x;
  assert jsonb_array_length(d -> 'airports') = n_ap, format('airports: the document has %s, the routes, legs and bases use %s', jsonb_array_length(d -> 'airports'), n_ap);
  select count(*) into n_air from public.airlines al
   where al.world_id = w
     and (exists (select 1 from public.groups g where g.id = al.group_id and g.kind = 'ours')
          or exists (select 1 from public.airline_bases b where b.airline_id = al.id)
          or exists (select 1 from public.aircraft a where a.airline_id = al.id)
          or exists (select 1 from public.routes r where r.airline_id = al.id and not r.removed)
          or exists (select 1 from public.rotations r where r.airline_id = al.id)
          or exists (select 1 from public.flight_legs l where l.airline_id = al.id));
  assert jsonb_array_length(d -> 'airlines') = n_air, format('airlines: the document has %s, ours and the ones the planning rows name are %s', jsonb_array_length(d -> 'airlines'), n_air);
  assert not exists (select 1 from jsonb_array_elements(d -> 'flight_legs') e(l)
                      where not exists (select 1 from jsonb_array_elements(d -> 'airports') a where a ->> 'code' = e.l ->> 'origin_code')
                         or not exists (select 1 from jsonb_array_elements(d -> 'airports') a where a ->> 'code' = e.l ->> 'dest_code')),
    'a leg names an airport the document leaves out';
  raise notice 'counts equal the tables'': % settings, % world rules, % types, % airports, % airlines, % bases, % aircraft, % routes, % rotations, % legs',
    (select count(*) from jsonb_object_keys(d -> 'settings')), (select count(*) from jsonb_object_keys(d -> 'world_rules')),
    jsonb_array_length(d -> 'aircraft_types'), n_ap, n_air, jsonb_array_length(d -> 'airline_bases'), jsonb_array_length(d -> 'aircraft'),
    jsonb_array_length(d -> 'routes'), jsonb_array_length(d -> 'rotations'), jsonb_array_length(d -> 'flight_legs');
end
$test$;

-- ---------------------------------------------------------------- 3. one leg, one airport and one setting read back exactly
do $test$
declare
  w bigint := (select (v #>> '{}')::bigint from t_ri where k = 'world');
  d jsonb := (select v from t_ri where k = 'doc');
  l public.flight_legs; dl jsonb;
  v_code text; da jsonb; a public.airports; wa public.world_airports;
  s public.settings;
begin
  select * into l from public.flight_legs x where x.world_id = w order by x.id limit 1;
  if found then
    select e into dl from jsonb_array_elements(d -> 'flight_legs') e where (e ->> 'id')::bigint = l.id;
    assert dl is not null, format('leg %s isn''t in the document', l.id);
    assert (dl ->> 'airline_id')::bigint = l.airline_id and (dl ->> 'rotation_id')::bigint = l.rotation_id
       and (dl ->> 'leg_no')::smallint = l.leg_no and (dl ->> 'flight_no')::int is not distinct from l.flight_no
       and dl ->> 'origin_code' = l.origin_code and dl ->> 'dest_code' = l.dest_code
       and (dl ->> 'aircraft_id')::bigint is not distinct from l.aircraft_id
       and (select array_agg(x::smallint order by o) from jsonb_array_elements_text(dl -> 'days_utc') with ordinality as t(x, o)) = l.days_utc
       and (dl ->> 'dep_utc_min')::smallint is not distinct from l.dep_utc_min and (dl ->> 'block_min')::smallint is not distinct from l.block_min,
      format('leg %s doesn''t read back exactly', l.id);
  end if;
  -- an airport with the most the world says about it: a night ban if any has one, else a minimum connection time
  select x.airport_code into v_code from public.world_airports x
   where x.world_id = w and x.airport_code in (select e ->> 'code' from jsonb_array_elements(d -> 'airports') e)
   order by (x.night_ban_from is not null) desc, (x.mct_min is not null) desc, (x.utc_offset_override is not null) desc, x.airport_code limit 1;
  assert v_code is not null, 'no airport in the document has a world_airports row';
  select e into da from jsonb_array_elements(d -> 'airports') e where e ->> 'code' = v_code;
  select * into a from public.airports x where x.code = v_code;
  select * into wa from public.world_airports x where x.world_id = w and x.airport_code = v_code;
  assert da ->> 'city' is not distinct from a.city and da ->> 'country_code' is not distinct from a.country_code
     and (da ->> 'lat')::numeric is not distinct from a.lat and (da ->> 'lon')::numeric is not distinct from a.lon
     and (da ->> 'utc_offset')::numeric is not distinct from coalesce(wa.utc_offset_override, a.utc_offset)
     and (da ->> 'utc_offset_override')::numeric is not distinct from wa.utc_offset_override
     and (da ->> 'mct_min')::smallint is not distinct from wa.mct_min
     and da ->> 'night_ban_from' is not distinct from to_char(wa.night_ban_from, 'HH24:MI')
     and da ->> 'night_ban_to' is not distinct from to_char(wa.night_ban_to, 'HH24:MI'),
    format('airport %s doesn''t read back exactly', v_code);
  -- a setting: the connection wait if there is one, else the first
  select * into s from public.settings x where x.world_id = w and x.airline_id is null order by (x.key = 'connection_max_wait_h') desc, x.key limit 1;
  assert d -> 'settings' -> s.key = s.value, format('setting %s doesn''t read back exactly', s.key);
  raise notice 'leg %, airport % and setting % read back exactly', coalesce(l.id::text, '(no legs)'), v_code, s.key;
end
$test$;

-- ---------------------------------------------------------------- 4. an airline's override wins over the world value
do $test$
declare
  w bigint := (select (v #>> '{}')::bigint from t_ri where k = 'world');
  d jsonb; al1 bigint; al2 bigint; o record; n int := 0;
begin
  select (e ->> 'id')::bigint into al1 from jsonb_array_elements((select v from t_ri where k = 'doc') -> 'airlines') e order by (e ->> 'id')::bigint limit 1;
  select (e ->> 'id')::bigint into al2 from jsonb_array_elements((select v from t_ri where k = 'doc') -> 'airlines') e
   where (e ->> 'id')::bigint <> al1 order by (e ->> 'id')::bigint limit 1;
  assert al1 is not null, 'the document has no airlines';
  perform set_config('equinox.actor', 'claude', true), set_config('equinox.actor_detail', 'rules_input test', true);
  insert into public.settings (world_id, airline_id, key, value, description)
  values (w, null, 'rules_input_test_key', '1', 'rules_input test: the world''s value'),
         (w, al1, 'rules_input_test_key', '2', 'rules_input test: one airline''s override');
  perform set_config('equinox.actor', '', true), set_config('equinox.actor_detail', '', true);
  d := public.rules_input();
  insert into t_ri values ('doc2', d);
  assert d #> '{settings,rules_input_test_key}' = '1'::jsonb, 'the world''s value isn''t the document''s setting';
  assert (select e #> '{settings,rules_input_test_key}' from jsonb_array_elements(d -> 'airlines') e where (e ->> 'id')::bigint = al1) = '2'::jsonb,
    'the airline''s override doesn''t win in its own settings';
  if al2 is not null then
    assert (select e #> '{settings,rules_input_test_key}' from jsonb_array_elements(d -> 'airlines') e where (e ->> 'id')::bigint = al2) = '1'::jsonb,
      'another airline doesn''t keep the world''s value';
  end if;
  -- the overrides the copy already has (Ryanair's fare and hubs-first exemption, say) read back the same way
  for o in select s.airline_id, s.key, s.value from public.settings s where s.world_id = w and s.airline_id is not null and s.key <> 'rules_input_test_key' loop
    assert (select e -> 'settings' -> o.key from jsonb_array_elements(d -> 'airlines') e where (e ->> 'id')::bigint = o.airline_id) = o.value,
      format('airline %s''s override of %s doesn''t win in its settings', o.airline_id, o.key);
    n := n + 1;
  end loop;
  raise notice 'an airline''s override wins in its own settings (and % override(s) already in the copy read back the same); the world''s value stays for the document and the others', n;
end
$test$;

-- ---------------------------------------------------------------- 5. who is refused, and what staff get
set local role anon;
do $test$
declare refused boolean := false;
begin
  begin perform public.rules_input(); exception when insufficient_privilege then refused := true; end;
  assert refused, 'signed out, rules_input() could be called';
end
$test$;
reset role;

do $$ begin perform set_config('request.jwt.claims',
  '{"sub": "00000000-0000-4000-8000-0000000000f1", "email": "rules-input-other@example.com", "role": "authenticated"}', true); end $$;
set local role authenticated;
do $test$
declare refused boolean := false;
begin
  begin perform public.rules_input(); exception when insufficient_privilege then refused := true; end;
  assert refused, 'an account that isn''t staff could read rules_input()';
end
$test$;
reset role;

do $$ begin perform set_config('request.jwt.claims',
  '{"sub": "00000000-0000-4000-8000-0000000000f2", "email": "rules-input-staff@example.com", "role": "authenticated"}', true); end $$;
set local role authenticated;
do $test$
begin
  assert public.rules_input() = (select v from t_ri where k = 'doc2'), 'staff don''t get what postgres gets';
end
$test$;
reset role;
do $test$ begin raise notice 'signed out and an account that isn''t staff are refused; staff get what postgres gets'; end $test$;

-- ---------------------------------------------------------------- 6. export_for_report(secret, 'rules')
insert into t_ri values ('secret', to_jsonb('rules-input-test-' || gen_random_uuid()::text));
insert into public.ingest_secret (secret) select v #>> '{}' from t_ri where k = 'secret';
set local role anon;
do $test$
declare s text := (select v #>> '{}' from t_ri where k = 'secret'); w text := (select v #>> '{}' from t_ri where k = 'world');
  want jsonb := (select v from t_ri where k = 'doc2'); refused boolean := false;
begin
  assert public.export_for_report(s, 'rules') = want, 'export_for_report(secret, rules) differs from rules_input()';
  assert public.export_for_report(s, 'rules', w) = want, 'export_for_report(secret, rules, the world''s id) differs from rules_input()';
  assert public.export_for_report(s, 'rules', '') = want, 'export_for_report(secret, rules, empty) differs from rules_input()';
  begin perform public.export_for_report(s || '-wrong', 'rules'); exception when others then refused := sqlerrm = 'not allowed'; end;
  assert refused, 'export_for_report(rules) with a wrong secret wasn''t refused';
end
$test$;
reset role;
do $test$ begin raise notice 'export_for_report(secret, rules), signed out as the scripts call it, gives rules_input()''s document; a wrong secret is refused'; end $test$;

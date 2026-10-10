-- The scripts' and the Photos screen's writes on the tables (#13 build, pull request 8; design §8). Run by
-- database/rehearse.sh on the copy of last night's backup, after the new migrations, inside a transaction that is
-- rolled back. A failed check stops with an error that says which (tables, codes and counts, never values).
--   1. planner_data_set(): the route research as it stands changes no row (the tables already hold it, by the loader's
--      rules); with one route's stars and one airport's city changed, exactly those two rows change, logged as actor
--      script, and planner_data holds the new document; a new UTC offset is written for an airport no flight uses and
--      held back (and named) for one a flight uses; a route the research adds is added, one it drops (with nothing
--      pointing at it) goes;
--   2. site_admin('content', 'mct'): the connection times as they stand change no row of world_airports; one time
--      changed changes exactly that row (actor script) and site_public() shows it, site_content.mct too; an airport
--      left out of the map loses its time; a map that isn't airport codes with whole minutes is refused;
--   3. site_set_airline_logo(): one of our airlines (from airlines) is taken, any other name refused.

-- ---------------------------------------------------------------- 1. planner_data_set()
do $test$
declare
  w bigint := (select id from public.worlds where is_default);
  s text := 'website-test-' || gen_random_uuid();
  d jsonb; d2 jsonb; d3 jsonb; res jsonb; t0 timestamptz; n bigint; bad text;
  v_i int; v_route bigint; v_stars int; v_code text; v_city text; v_used text; v_free text; v_off numeric;
  v_new_dest text; v_al text; v_hub text; v_drop bigint; v_drop_key text[];
begin
  insert into public.ingest_secret (secret) values (s);
  select x.value into d from public.planner_data x where x.key = 'DATA';
  assert jsonb_typeof(d -> 'routes') = 'array' and jsonb_typeof(d -> 'coords') = 'object' and jsonb_typeof(d -> 'utc') = 'object',
    'the copy has no route research to test with';

  -- the research as it stands: nothing to write
  t0 := clock_timestamp();
  res := public.planner_data_set(s, 'DATA', d);
  select string_agg(x.table_name || ' ' || x.op || ' ×' || x.n, ', ') into bad
    from (select c.table_name, c.op, count(*) as n from public.change_log c where c.changed_at >= t0 group by 1, 2) x;
  assert bad is null, 'planner_data_set() with the research as it stands changed rows: ' || bad;
  assert res ->> 'ok' = 'true' and (res ->> 'bytes')::int = length(d::text), 'planner_data_set() doesn''t answer ok and bytes as before';

  -- one research route's stars and one airport's city: the first route the research lists that the planner hasn't added
  select e.ord::int, ro.id, private.json_int(e.v -> 7)::int into v_i, v_route, v_stars
    from jsonb_array_elements(d -> 'routes') with ordinality as e(v, ord)
    join public.airlines al on al.world_id = w and al.planner_name = e.v ->> 0
    join public.routes ro on ro.airline_id = al.id and ro.hub_code = e.v ->> 1 and ro.dest_code = e.v ->> 2 and ro.source = 'research'
   order by e.ord limit 1;
  assert v_route is not null, 'no research route to change';
  v_stars := case when coalesce(v_stars, 0) >= 5 then 4 else coalesce(v_stars, 0) + 1 end;
  select min(k) into v_code from jsonb_object_keys(d -> 'coords') k where jsonb_typeof(d -> 'coords' -> k) = 'array';
  v_city := coalesce(d -> 'coords' -> v_code ->> 2, '') || ' (test)';
  d2 := jsonb_set(jsonb_set(d, array['routes', (v_i - 1)::text, '7'], to_jsonb(v_stars)), array['coords', v_code, '2'], to_jsonb(v_city));
  t0 := clock_timestamp();
  res := public.planner_data_set(s, 'DATA', d2);
  select string_agg(format('%s %s %s', c.table_name, c.op, c.row_key), ', ') into bad from public.change_log c
   where c.changed_at >= t0
     and not (c.table_name = 'routes' and c.op = 'update' and c.row_key = jsonb_build_object('id', v_route)
              and c.new_values = jsonb_build_object('stars', v_stars))
     and not (c.table_name = 'airports' and c.op = 'update' and c.row_key = jsonb_build_object('code', v_code)
              and c.new_values = jsonb_build_object('city', v_city));
  assert bad is null, 'planner_data_set() changed more than the route''s stars and the airport''s city: ' || bad;
  select count(*) into n from public.change_log c where c.changed_at >= t0 and c.actor = 'script' and c.actor_detail = 'planner_data_set';
  assert n = 2, format('planner_data_set() logged %s of the 2 changes as actor script', n);
  assert (select stars from public.routes where id = v_route) = v_stars and (select city from public.airports where code = v_code) = v_city,
    'the route''s stars or the airport''s city isn''t what planner_data_set() was given';
  assert (select value from public.planner_data where key = 'DATA') = d2, 'planner_data doesn''t hold the new research';
  assert (res -> 'tables' ->> 'routes')::int = 1 and (res -> 'tables' ->> 'airports')::int = 1,
    'planner_data_set() doesn''t answer the one route and one airport it changed';

  -- offsets: one for an airport a flight uses (held back, named), one for an airport no flight or plan uses (written)
  select l.origin_code into v_used from public.flight_legs l
   where l.world_id = w and d -> 'utc' ? l.origin_code
     and not exists (select 1 from public.world_airports x where x.world_id = w and x.airport_code = l.origin_code and x.utc_offset_override is not null)
   order by l.id limit 1;
  select k into v_free from jsonb_object_keys(d -> 'utc') k
   where private.json_num(d -> 'utc' -> k) is not null
     and not exists (select 1 from public.flight_legs l where l.origin_code = k or l.dest_code = k)
     and not exists (select 1 from public.plan_card_legs l where l.origin_code = k or l.dest_code = k)
   order by k limit 1;
  assert v_used is not null and v_free is not null, 'no airports to test offsets with';
  d3 := d2;
  for v_code in select unnest(array[v_used, v_free]) loop
    v_off := private.json_num(d -> 'utc' -> v_code);
    d3 := jsonb_set(d3, array['utc', v_code], to_jsonb(case when v_off >= 13 then v_off - 1 else v_off + 1 end));
  end loop;
  res := public.planner_data_set(s, 'DATA', d3);
  assert res -> 'tables' -> 'utc offsets held back' = jsonb_build_array(v_used),
    format('planner_data_set() didn''t hold back exactly the offset of %s, which a flight uses: %s', v_used, res -> 'tables' -> 'utc offsets held back');
  assert (select utc_offset from public.airports where code = v_used) is not distinct from round(private.json_num(d -> 'utc' -> v_used), 2),
    'the offset of an airport a flight uses was changed';
  assert (select utc_offset from public.airports where code = v_free) = round(private.json_num(d3 -> 'utc' -> v_free), 2),
    'the offset of an airport no flight uses wasn''t written';

  -- a route the research adds, and a research route it drops that nothing points at
  select al.planner_name, ro.hub_code into v_al, v_hub from public.routes ro join public.airlines al on al.id = ro.airline_id
   where ro.id = v_route;
  select a.code into v_new_dest from public.airports a
   where a.code <> v_hub and not exists (select 1 from public.routes ro join public.airlines al on al.id = ro.airline_id
                                          where al.planner_name = v_al and ro.hub_code = v_hub and ro.dest_code = a.code)
   order by a.code limit 1;
  select ro.id, array[al.planner_name, ro.hub_code, ro.dest_code] into v_drop, v_drop_key
    from public.routes ro join public.airlines al on al.id = ro.airline_id
   where ro.world_id = w and ro.source = 'research' and ro.id <> v_route
     and not ro.removed and ro.removed_note is null and ro.city_override is null and ro.distance_override_km is null
     and ro.market_override_id is null and not ro.market_cleared and ro.stars_override is null and not ro.edit_kept and ro.cabin_choice is null
     and not exists (select 1 from public.rotations o where o.route_id = ro.id)
     and not exists (select 1 from public.fare_plan o where o.route_id = ro.id)
     and not exists (select 1 from public.game_flights o where o.route_id = ro.id)
   order by ro.id limit 1;
  assert v_new_dest is not null and v_drop is not null, 'no route to add or drop in the test';
  d3 := jsonb_set(d3, '{routes}', (select jsonb_agg(e.v order by e.ord) from jsonb_array_elements(d3 -> 'routes') with ordinality e(v, ord)
                                    where array[e.v ->> 0, e.v ->> 1, e.v ->> 2] is distinct from v_drop_key)
                                  || jsonb_build_array(jsonb_build_array(v_al, v_hub, v_new_dest, 'Test city', 'Test', 1234, '', 3)));
  t0 := clock_timestamp();
  res := public.planner_data_set(s, 'DATA', d3);
  assert (select count(*) from public.routes ro join public.airlines al on al.id = ro.airline_id
           where al.planner_name = v_al and ro.hub_code = v_hub and ro.dest_code = v_new_dest and ro.source = 'research'
             and ro.city = 'Test city' and ro.distance_km = 1234 and ro.stars = 3) = 1,
    'the route the research adds isn''t there with its figures';
  assert not exists (select 1 from public.routes where id = v_drop), 'the research route the research dropped is still there';
  select string_agg(format('%s %s', c.table_name, c.op), ', ') into bad from public.change_log c
   where c.changed_at >= t0 and not (c.table_name = 'routes' and c.op in ('insert', 'delete'));
  assert bad is null, 'adding and dropping a route changed more: ' || bad;

  raise notice 'planner_data_set(): the research as it stands changes nothing; one route''s stars and one airport''s city change exactly those 2 rows (actor script); an offset a flight uses is held back and named, another written; a route added and one dropped';
  delete from public.ingest_secret where secret = s;
end
$test$;

-- ---------------------------------------------------------------- 2. site_admin('content', 'mct')
do $test$
declare
  w bigint := (select id from public.worlds where is_default);
  s text := 'website-test-' || gen_random_uuid();
  m jsonb; m2 jsonb; t0 timestamptz; bad text; v_code text; v_gone text; v_new int; refused boolean; n int;
begin
  insert into public.ingest_secret (secret) values (s);
  select x.value into m from public.site_content x where x.key = 'mct';
  assert jsonb_typeof(m) = 'object', 'the copy has no connection times (site_content.mct)';

  -- the times as they stand: world_airports already holds them
  t0 := clock_timestamp();
  assert public.site_admin(s, 'content', jsonb_build_object('key', 'mct', 'value', m)) = '{"ok": true}'::jsonb, 'site_admin() doesn''t answer ok';
  select string_agg(format('%s %s', c.op, c.row_key ->> 'airport_code'), ', ') into bad from public.change_log c
   where c.changed_at >= t0 and c.table_name = 'world_airports';
  assert bad is null, 'site_admin() with the connection times as they stand changed world_airports: ' || bad;

  -- one time changed, at an airport that isn't a hub or base
  select min(k) into v_code from jsonb_object_keys(m) k
   where not exists (select 1 from public.airline_bases b where b.world_id = w and b.airport_code = k);
  v_new := least(1440, private.json_int(m -> v_code) + 5);
  if v_new = private.json_int(m -> v_code) then v_new := v_new - 5; end if;
  m2 := jsonb_set(m, array[v_code], to_jsonb(v_new));
  t0 := clock_timestamp();
  perform public.site_admin(s, 'content', jsonb_build_object('key', 'mct', 'value', m2));
  select string_agg(format('%s %s %s', c.table_name, c.op, c.row_key), ', ') into bad from public.change_log c
   where c.changed_at >= t0
     and not (c.table_name = 'world_airports' and c.op = 'update' and c.row_key = jsonb_build_object('world_id', w, 'airport_code', v_code)
              and c.new_values = jsonb_build_object('mct_min', v_new) and c.actor = 'script' and c.actor_detail = 'site_admin');
  assert bad is null, 'changing one connection time changed more, or wasn''t logged as the script: ' || bad;
  assert (select count(*) from public.change_log c where c.changed_at >= t0) = 1, 'changing one connection time wrote no change';
  assert (public.site_public() -> 'content' -> 'mct' ->> v_code)::int = v_new, 'site_public() doesn''t show the new connection time';
  assert (select value from public.site_content where key = 'mct') = m2, 'site_content.mct isn''t kept in step';

  -- an airport left out of the map loses its time
  select min(k) into v_gone from jsonb_object_keys(m2) k
   where k <> v_code and not exists (select 1 from public.airline_bases b where b.world_id = w and b.airport_code = k);
  perform public.site_admin(s, 'content', jsonb_build_object('key', 'mct', 'value', m2 - v_gone));
  assert not exists (select 1 from public.world_airports x where x.world_id = w and x.airport_code = v_gone and x.mct_min is not null),
    'an airport left out of the map keeps its connection time';
  assert not (public.site_public() -> 'content' -> 'mct' ? v_gone), 'site_public() still shows a connection time left out of the map';
  select count(*) into n from jsonb_object_keys(public.site_public() -> 'content' -> 'mct');
  assert n = (select count(*) from jsonb_object_keys(m2 - v_gone)), 'site_public() doesn''t show exactly the map''s connection times';

  -- refused: a time that isn't whole minutes, or a key that isn't an airport code
  for m2 in select jsonb_build_object(v_code, 52.5) union all select jsonb_build_object('abc', 60) union all select '[60]'::jsonb loop
    refused := false;
    begin
      perform public.site_admin(s, 'content', jsonb_build_object('key', 'mct', 'value', m2));
    exception when invalid_parameter_value then refused := true;
    end;
    assert refused, 'site_admin() took connection times that aren''t airport codes with whole minutes';
  end loop;

  raise notice 'site_admin(''content'', ''mct''): the times as they stand change nothing (% airports); one time changed changes exactly that world_airports row (actor script), and site_public() and site_content.mct show it; a time left out goes; bad maps refused',
    (select count(*) from jsonb_object_keys(m));
  delete from public.ingest_secret where secret = s;
end
$test$;

-- ---------------------------------------------------------------- 3. site_set_airline_logo(): our airlines, from airlines
insert into public.planner_users (email) values ('website-scripts-staff@example.com') on conflict do nothing;
insert into public.airlines (world_id, game_id, planner_name, public_name, active)
select id, 999999, 'Rival Test Air', 'Rival Test Air', true from public.worlds where is_default;
do $$ begin perform set_config('request.jwt.claims',
  '{"sub": "00000000-0000-4000-8000-0000000000b8", "email": "website-scripts-staff@example.com", "role": "authenticated"}', true); end $$;
set local role authenticated;
do $test$
declare refused boolean; v_al text;
begin
  assert public.is_planner_user(), 'the test account isn''t staff';
  for v_al in select unnest(array['Kingfisher', 'Malaysia Airlines']) loop
    assert public.site_set_airline_logo(v_al, 'https://example.com/logo.png') = '{"ok": true}'::jsonb,
      format('site_set_airline_logo() refused %s, one of our airlines', v_al);
  end loop;
  for v_al in select unnest(array['Lufthansa', 'Rival Test Air', '']) loop
    refused := false;
    begin
      perform public.site_set_airline_logo(v_al, 'https://example.com/logo.png');
    exception when raise_exception then refused := true;
    end;
    assert refused, format('site_set_airline_logo() took %s, which isn''t one of our airlines', coalesce(nullif(v_al, ''), 'an empty name'));
  end loop;
  raise notice 'site_set_airline_logo(): our airlines taken (from airlines); a name that isn''t ours refused, a rival in airlines included';
end
$test$;
reset role;

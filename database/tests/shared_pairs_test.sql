-- Shared city pairs, the data and the fare ladder (spec docs/specs/2026-11-05-shared-pairs.md §1, §2 and §6; migration
-- 20261105000000_shared_pairs.sql). Run by database/rehearse.sh on the copy of last night's backup, after the new
-- migrations, inside a transaction that is rolled back. Last night's backup has no joined pair, so every case is built
-- here in a world of its own. A failed check stops with an error that says which (codes, levels and counts of the
-- hand-made world only, never rows of the copy).
--   1. The objects: routes.shares_route_id (described; its foreign key with the world, the check, the unique index, the
--      trigger); the four settings in every world (the default world's Ryanair excluded); the view shared_pairs
--      (security_invoker, select for authenticated only, described with every column); join_pair() staff only, as owner
--      with an empty search path, described; check_route_share() internal; the ladder's descriptions.
--   2. The hand-made world: OA (bases SA1, SA2, SA3 in India), JB (SB1, SB2, SB3 in the US; station SS1), RX excluded as
--      Ryanair is (SR1). shared_pairs lists the 9 base-to-base pairs of OA and JB and none of RX's or the station's; the
--      owner is the airline whose row exists (JB on SB3–SA3, though the country rule says OA), else the country rule's
--      (OA on SA3–SB2, US–India).
--   3. join_pair(): SA1–SB1 joined by JB (a row from SB1 to SA1 copying stars, the market, the distance and the cabin
--      choice, shares_route_id set, logged as claude with detail join_pair); refused: Ryanair's pair, a station's, a second
--      joiner, a joiner's own route; the trigger refuses a row naming its own airline's route or a joiner's route. Six
--      pairs joined: the seventh refused within shared_pairs_limit_days of shared_pairs_from, allowed after them.
--      Signed out and an account that isn't staff are refused.
--   4. The ladder on SA1–SB1 at Saturday 19 Jan 2030 12:00 UTC, both airlines flying it daily since 1 Dec, OA at 110 both
--      ways on its fare plan, the game's default 200 read under OA only:
--      - OA (owner) judged on both routes' flights: SA1→SB1 its 7 sold out and JB's 7 not, 7 of 14 sold out, steps down;
--        SB1→SA1 14 of 14, steps up; shared_with JB; its own fares at 110, no set-back.
--      - JB (joiner) follows: level 110 both ways (OA's), never a move of its own, nothing to plan; its SB1→SA1 fares at
--        100% of the default it reads from OA's market run: one set-back to 110 ("the pair's level"), its only action.
--      - A rotation added by JB (15 Jan) holds OA's pair both ways ("a flight added on 15 Jan by JB"); JB's route, new by
--        its first rotation, still isn't a new route to its ladder.
--      - OA's moves put on its fare plan (105 out, 115 back): JB's next read shows the pair's move and sets both its
--        directions back to the new levels, as two set-backs.
--   5. On the copy: the shared pairs it lists (none joined), and fare_ladder()'s builder timed for every one of our
--      airlines after the change, beside the same calls before it (rehearsal_before.fare_ladder_ms,
--      database/tests/before/frequencies_and_fares_before.sql); each under the 30 s limit and not noticeably slower
--      (at most a quarter and a second more).

create temporary table t_sp (k text primary key, v jsonb) on commit drop;
grant select, insert, update on t_sp to anon, authenticated;
insert into public.planner_users (email) values ('shared-pairs-staff@example.com') on conflict do nothing;

-- ---------------------------------------------------------------- 1. the objects
do $test$
declare bad text; f text := 'public.join_pair(bigint)'; g text := 'private.check_route_share()'; dw bigint := (select id from public.worlds where is_default);
  r text;
begin
  assert length(coalesce(col_description('public.routes'::regclass,
                  (select attnum from pg_attribute where attrelid = 'public.routes'::regclass and attname = 'shares_route_id')), '')) > 100,
    'routes.shares_route_id isn''t there or isn''t described';
  assert (select pg_get_constraintdef(oid) from pg_constraint where conname = 'routes_shares_route_fkey')
         = 'FOREIGN KEY (shares_route_id, world_id) REFERENCES routes(id, world_id)',
    'routes.shares_route_id''s foreign key isn''t to routes (id, world_id)';
  assert exists (select 1 from pg_constraint where conname = 'routes_shares_not_itself' and contype = 'c'), 'routes has no shares_route_id check';
  assert (select i.indisunique from pg_index i where i.indexrelid = 'public.routes_shares_route_id_key'::regclass), 'routes.shares_route_id has no unique index';
  assert exists (select 1 from pg_trigger t where t.tgrelid = 'public.routes'::regclass and t.tgname = 'check_route_share' and not t.tgisinternal),
    'routes has no check_route_share trigger';
  -- the settings, in every world; the default world's Ryanair excluded
  select string_agg(w.name || ' ' || k.key, ', ') into bad
    from public.worlds w cross join unnest(array['shared_pairs_excluded_airlines', 'shared_pairs_from', 'shared_pairs_limit', 'shared_pairs_limit_days']) k (key)
   where not exists (select 1 from public.settings s where s.world_id = w.id and s.airline_id is null and s.key = k.key and length(coalesce(s.description, '')) > 50);
  assert bad is null, 'settings missing or not described: ' || bad;
  assert (select s.value from public.settings s where s.world_id = dw and s.airline_id is null and s.key = 'shared_pairs_excluded_airlines')
         = coalesce((select jsonb_agg(a.id order by a.id) from public.airlines a where a.world_id = dw and a.planner_name = 'Ryanair'), '[]'::jsonb),
    'the default world''s excluded airlines aren''t its Ryanair';
  assert (select jsonb_typeof(s.value) = 'string' and s.value #>> '{}' ~ '^\d{4}-\d{2}-\d{2}$' from public.settings s
           where s.world_id = dw and s.airline_id is null and s.key = 'shared_pairs_from'), 'shared_pairs_from isn''t a date';
  assert (select s.value from public.settings s where s.world_id = dw and s.airline_id is null and s.key = 'shared_pairs_limit') = '6'::jsonb
     and (select s.value from public.settings s where s.world_id = dw and s.airline_id is null and s.key = 'shared_pairs_limit_days') = '14'::jsonb,
    'the limit isn''t 6 pairs for 14 days';
  -- the view
  assert (select coalesce('security_invoker=true' = any (c.reloptions), false) from pg_class c where c.oid = 'public.shared_pairs'::regclass),
    'shared_pairs isn''t security_invoker';
  assert has_table_privilege('authenticated', 'public.shared_pairs', 'select') and not has_table_privilege('anon', 'public.shared_pairs', 'select'),
    'shared_pairs isn''t select for signed in only';
  foreach r in array array['insert', 'update', 'delete', 'truncate', 'references', 'trigger'] loop
    assert not has_table_privilege('authenticated', 'public.shared_pairs', r), 'authenticated has ' || r || ' on shared_pairs';
  end loop;
  assert length(coalesce(obj_description('public.shared_pairs'::regclass, 'pg_class'), '')) > 200, 'shared_pairs has no description';
  select string_agg(a.attname, ', ') into bad from pg_attribute a
   where a.attrelid = 'public.shared_pairs'::regclass and a.attnum > 0 and not a.attisdropped and coalesce(col_description(a.attrelid, a.attnum), '') = '';
  assert bad is null, 'shared_pairs columns without a description: ' || bad;
  -- join_pair(): signed in only, as owner, empty search path
  assert (select p.prosecdef and p.provolatile = 'v' and coalesce('search_path=""' = any (p.proconfig), false) from pg_proc p where p.oid = f::regprocedure),
    f || ' isn''t volatile, as owner with an empty search path';
  assert not has_function_privilege('anon', f, 'execute') and has_function_privilege('authenticated', f, 'execute'), f || ' isn''t signed in only';
  assert not exists (select 1 from pg_proc p cross join aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                      where p.oid = f::regprocedure and a.grantee = 0), f || ' is open to public';
  assert length(coalesce(obj_description(f::regprocedure, 'pg_proc'), '')) > 200, f || ' has no description';
  assert not has_function_privilege('anon', g, 'execute') and not has_function_privilege('authenticated', g, 'execute'), g || ' can be called from outside';
  assert length(coalesce(obj_description(g::regprocedure, 'pg_proc'), '')) > 100, g || ' has no description';
  assert obj_description('private.fig_fare_ladder(bigint, timestamptz)'::regprocedure, 'pg_proc') like '%Shared pairs (since 5 Nov%'
     and obj_description('public.fare_ladder(bigint, timestamptz)'::regprocedure, 'pg_proc') like '%a shared pair has one ladder, the owner''s%',
    'the fare ladder''s descriptions don''t say how a shared pair is judged';
  raise notice 'routes.shares_route_id described, its foreign key with the world, check, unique index and trigger; the four settings in every world (the default world''s Ryanair excluded, 6 pairs for 14 days); shared_pairs security_invoker, select for signed in only, every column described; join_pair() signed in only, as owner, described; check_route_share() internal';
end
$test$;

-- ---------------------------------------------------------------- the hand-made world
-- a route's flying: a rotation launched on `launched`, an aircraft, its two legs daily, its first fares on 2 Dec 2029 and
-- 7 days each way in the week before Saturday 19 Jan 2030 12:00 UTC (12 to 18 Jan), economy only: out (from the route's
-- hub) at out_pct full and out_fare, back at back_pct and back_fare
create function pg_temp.sp_fly(w bigint, al bigint, r bigint, k int, ty bigint, cfg bigint, launched date, first_fare numeric,
                               out_pct int, out_fare numeric, back_pct int, back_fare numeric)
returns bigint language plpgsql as $f$
declare rot bigint; ac bigint; i int; t timestamptz; hub text; dest text;
begin
  select ro.hub_code, ro.dest_code into hub, dest from public.routes ro where ro.id = r;
  insert into public.rotations (world_id, airline_id, route_id, launched_on) values (w, al, r, launched) returning id into rot;
  insert into public.aircraft (world_id, airline_id, registration, aircraft_type_id, cabin_config_id, status, base_code, acquired)
  values (w, al, 'SP-' || k, ty, cfg, 'active', hub, 'new') returning id into ac;
  insert into public.flight_legs (world_id, airline_id, rotation_id, leg_no, flight_no, origin_code, dest_code, aircraft_id, days_utc, dep_utc_min, block_min) values
    (w, al, rot, 1, 7000 + k * 2, hub, dest, ac, '{1,2,3,4,5,6,7}', 840, 60),
    (w, al, rot, 2, 7001 + k * 2, dest, hub, ac, '{1,2,3,4,5,6,7}', 1080, 60);
  for i in 0 .. 1 loop
    t := timestamptz '2029-12-02 14:00:00+00' + make_interval(hours => i * 4);
    insert into public.game_flights (world_id, airline_id, game_date, flight_no, origin_code, dest_code, dep_local, dep_at, registration,
                                     eco_pax, eco_seats, eco_pct, eco_fare, loads_captured_at)
    values (w, al, date '2029-12-02', 7000 + k * 2 + i, case when i = 0 then hub else dest end, case when i = 0 then dest else hub end,
            to_char(t at time zone 'UTC', 'HH24:MI'), t, 'SP-' || k, 180, 180, 100, first_fare, t + interval '1 day');
  end loop;
  for i in 0 .. 13 loop
    t := timestamptz '2030-01-12 14:00:00+00' + make_interval(days => i / 2, hours => (i % 2) * 4);
    insert into public.game_flights (world_id, airline_id, game_date, flight_no, origin_code, dest_code, dep_local, dep_at, registration,
                                     eco_pax, eco_seats, eco_pct, eco_fare, loads_captured_at)
    values (w, al, (t at time zone 'UTC')::date, 7000 + k * 2 + i % 2, case when i % 2 = 0 then hub else dest end,
            case when i % 2 = 0 then dest else hub end, to_char(t at time zone 'UTC', 'HH24:MI'), t, 'SP-' || k,
            case when i % 2 = 0 then out_pct else back_pct end * 180 / 100, 180,
            case when i % 2 = 0 then out_pct else back_pct end, case when i % 2 = 0 then out_fare else back_fare end,
            timestamptz '2030-01-19 11:00:00+00');
  end loop;
  return rot;
end
$f$;

-- a ladder's economy row for one direction (by its airports), as "level>new_level move kind fix"
create function pg_temp.sp_line(d jsonb, dfrom text, dto text) returns text language sql as $f$
  select format('%s>%s %s %s %s', x ->> 'level', x ->> 'new_level', x ->> 'move', coalesce(x ->> 'ladder_kind', '-'),
                case when (x ->> 'fix')::boolean then 'fix' else 'ok' end)
    from jsonb_array_elements(d -> 'routes') x where x ->> 'from' = dfrom and x ->> 'to' = dto and x ->> 'cabin' = 'economy'
$f$;
create function pg_temp.sp_row(d jsonb, dfrom text, dto text) returns jsonb language sql as $f$
  select x from jsonb_array_elements(d -> 'routes') x where x ->> 'from' = dfrom and x ->> 'to' = dto and x ->> 'cabin' = 'economy'
$f$;
create function pg_temp.sp_id(name text) returns bigint language sql as $f$ select (v #>> '{}')::bigint from t_sp where k = name $f$;

do $setup$
declare
  dw bigint := (select id from public.worlds where is_default);
  w bigint; g bigint; oa bigint; jb bigint; rx bigint; ty bigint; cy bigint; r bigint;
begin
  perform set_config('equinox.actor', 'claude', true), set_config('equinox.actor_detail', 'shared pairs test', true);
  insert into public.countries (code, name, region) values ('IN', 'India', 'South Asia'), ('US', 'United States', 'North America'), ('FR', 'France', 'Europe')
  on conflict (code) do nothing;
  insert into public.airports (code, city, country_code, utc_offset)
  select c, 'City ' || c, case when c like 'SA%' then 'IN' when c like 'SR%' then 'FR' else 'US' end, 0
    from unnest(array['SA1', 'SA2', 'SA3', 'SB1', 'SB2', 'SB3', 'SR1', 'SS1']) c
  on conflict (code) do update set city = excluded.city, country_code = excluded.country_code, utc_offset = excluded.utc_offset;
  insert into public.worlds (name, game_host, kind) values ('shared pairs test', 'shared-pairs.test', 'exclusive') returning id into w;
  insert into public.settings (world_id, airline_id, key, value, unit, description)
  select w, null, s.key, s.value, s.unit, s.description from public.settings s where s.world_id = dw and s.airline_id is null;
  insert into public.world_rules (world_id, key, value, kind, unit, description)
  select w, r2.key, r2.value, r2.kind, r2.unit, r2.description from public.world_rules r2 where r2.world_id = dw;
  insert into public.groups (world_id, name, kind) values (w, 'ours', 'ours') returning id into g;
  insert into public.airlines (world_id, group_id, game_id, planner_name, public_name, iata_code, home_airport_code, active, position) values
    (w, g, 990601, 'Shared OA', 'OA', 'OA', 'SA1', true, 1),
    (w, g, 990602, 'Shared JB', 'JB', 'JB', 'SB1', true, 2),
    (w, g, 990603, 'Shared RX', 'RX', 'RX', 'SR1', true, 3);
  select id into oa from public.airlines where world_id = w and iata_code = 'OA';
  select id into jb from public.airlines where world_id = w and iata_code = 'JB';
  select id into rx from public.airlines where world_id = w and iata_code = 'RX';
  update public.settings set value = jsonb_build_array(rx) where world_id = w and airline_id is null and key = 'shared_pairs_excluded_airlines';
  update public.settings set value = to_jsonb(current_date::text) where world_id = w and airline_id is null and key = 'shared_pairs_from';
  insert into public.airline_bases (world_id, airline_id, airport_code, role, is_main, position) values
    (w, oa, 'SA1', 'hub', true, 1), (w, oa, 'SA2', 'focus', false, 2), (w, oa, 'SA3', 'focus', false, 3),
    (w, jb, 'SB1', 'hub', true, 1), (w, jb, 'SB2', 'hub', false, 2), (w, jb, 'SB3', 'focus', false, 3), (w, jb, 'SS1', 'station', false, 4),
    (w, rx, 'SR1', 'focus', false, 1);
  insert into public.aircraft_types (world_id, name, min_turn_min, cruise_kmh) values (w, 'SHARED TEST TYPE', 60, 800) returning id into ty;
  insert into public.cabin_configs (world_id, code, aircraft_type_id, cabin, seats, business_seats, economy_seats) values
    (w, 'SP-Y', ty, 'Leisure', 180, 0, 180) returning id into cy;
  -- OA's list: seven pairs with JB's bases, RX's pair, JB's station; JB's: SB3–SA3 (the country rule would give it OA)
  insert into public.routes (world_id, airline_id, hub_code, dest_code, distance_km, stars, stars_override, cabin_choice, source)
  select w, oa, x.h, x.d, 1200, 4, x.so, 'Leisure', 'research'
    from (values ('SA1', 'SB1', 5::smallint), ('SA1', 'SB2', null), ('SA1', 'SB3', null), ('SA2', 'SB1', null), ('SA2', 'SB2', null),
                 ('SA2', 'SB3', null), ('SA3', 'SB1', null), ('SA1', 'SR1', null), ('SA1', 'SS1', null)) x (h, d, so);
  insert into public.routes (world_id, airline_id, hub_code, dest_code, distance_km, source) values (w, jb, 'SB3', 'SA3', 1200, 'research');
  insert into t_sp values ('w', to_jsonb(w)), ('oa', to_jsonb(oa)), ('jb', to_jsonb(jb)), ('rx', to_jsonb(rx)), ('ty', to_jsonb(ty)), ('cy', to_jsonb(cy)),
    ('t', to_jsonb(timestamptz '2030-01-19 12:00:00+00'));
  insert into t_sp select 'r ' || ro.hub_code || '-' || ro.dest_code, to_jsonb(ro.id) from public.routes ro where ro.world_id = w;
end
$setup$;

-- ---------------------------------------------------------------- 2. the view, before any join
do $test$
declare w bigint := pg_temp.sp_id('w'); oa bigint := pg_temp.sp_id('oa'); jb bigint := pg_temp.sp_id('jb'); got text;
begin
  select string_agg(format('%s-%s %s%s', p.owner_base, p.joiner_base, case p.owner_airline_id when oa then 'OA' when jb then 'JB' else '?' end,
                           case when p.owner_route_id is null then ' unlisted' else '' end), ', ' order by p.owner_base, p.joiner_base) into got
    from public.shared_pairs p where p.world_id = w;
  assert got = 'SA1-SB1 OA, SA1-SB2 OA, SA1-SB3 OA, SA2-SB1 OA, SA2-SB2 OA, SA2-SB3 OA, SA3-SB1 OA, SA3-SB2 OA unlisted, SB3-SA3 JB',
    'shared_pairs isn''t the 9 pairs of OA''s and JB''s bases (JB owning SB3–SA3 by its row, OA SA3–SB2 by the country rule): ' || coalesce(got, 'none');
  assert not exists (select 1 from public.shared_pairs p where p.world_id = w and (p.joiner_route_id is not null or p.joined_on is not null or p.owner_flights_week <> 0)),
    'a pair is joined or flown before anything joined or flew';
  assert (select p.owner_route_id = pg_temp.sp_id('r SA1-SB1') and p.joiner_airline_id = jb from public.shared_pairs p where p.world_id = w and p.owner_base = 'SA1' and p.joiner_base = 'SB1'),
    'SA1–SB1''s owner route or joiner isn''t OA''s row and JB';
  raise notice 'shared_pairs: the 9 pairs of OA''s and JB''s hubs and focus cities, none of RX''s (excluded) or JB''s station; JB owns SB3–SA3 by its row though the country rule says OA; OA owns SA3–SB2, on neither list, by the country rule (US–India)';
end
$test$;

-- ---------------------------------------------------------------- 3. join_pair()
do $test$
declare w bigint := pg_temp.sp_id('w'); oa bigint := pg_temp.sp_id('oa'); jb bigint := pg_temp.sp_id('jb'); o bigint := pg_temp.sp_id('r SA1-SB1');
  r jsonb; j record; msg text; n int := 0; l record;
begin
  -- the actor as the Scheduling chat leaves it: none named, so claude
  perform set_config('equinox.actor', '', true), set_config('equinox.actor_detail', '', true);
  r := public.join_pair(o);
  assert (r ->> 'ok')::boolean and (r ->> 'joiner_airline_id')::bigint = jb and r ->> 'hub' = 'SB1' and r ->> 'dest' = 'SA1' and not (r ->> 'reused')::boolean
     and (r ->> 'joined')::int = 1 and (r #>> '{limit,pairs}')::int = 6 and (r #>> '{limit,until}')::date = current_date + 14,
    'join_pair() didn''t answer JB''s new row from SB1 to SA1, the first of 6 until 14 days on: ' || r::text;
  select ro.* into j from public.routes ro where ro.id = (r ->> 'route_id')::bigint;
  assert j.world_id = w and j.airline_id = jb and j.hub_code = 'SB1' and j.dest_code = 'SA1' and j.shares_route_id = o and j.stars = 4 and j.stars_override = 5
     and j.distance_km = 1200 and j.cabin_choice = 'Leisure' and j.source = 'added' and j.city = 'City SA1' and j.country_label = 'IN' and not j.removed,
    'JB''s row doesn''t copy OA''s (stars 4, override 5, 1200 km, Leisure) with shares_route_id set';
  select c.actor, c.actor_detail into l from public.change_log c where c.table_name = 'routes' and c.op = 'insert' and c.row_key = jsonb_build_object('id', j.id);
  assert l.actor = 'claude' and l.actor_detail = 'join_pair', 'the join isn''t logged as claude, join_pair: ' || coalesce(l.actor, 'none') || ' ' || coalesce(l.actor_detail, '');
  assert current_setting('equinox.actor', true) = '', 'join_pair() didn''t give back the caller''s actor';
  perform set_config('equinox.actor', 'claude', true), set_config('equinox.actor_detail', 'shared pairs test', true);
  insert into t_sp values ('j SB1-SA1', to_jsonb(j.id));
  -- refused
  begin perform public.join_pair(pg_temp.sp_id('r SA1-SR1')); exception when invalid_parameter_value then get stacked diagnostics msg = message_text;
    assert msg like '%RX neither joins nor is joined%', 'Ryanair''s pair refused for another reason: ' || msg; n := n + 1; end;
  begin perform public.join_pair(pg_temp.sp_id('r SA1-SS1')); exception when invalid_parameter_value then get stacked diagnostics msg = message_text;
    assert msg like '%isn''t a shared pair%', 'the station''s pair refused for another reason: ' || msg; n := n + 1; end;
  begin perform public.join_pair(o); exception when invalid_parameter_value then get stacked diagnostics msg = message_text;
    assert msg like '%has a joiner already%', 'a second joiner refused for another reason: ' || msg; n := n + 1; end;
  begin perform public.join_pair(j.id); exception when invalid_parameter_value then get stacked diagnostics msg = message_text;
    assert msg like '%is a joiner''s route%', 'a joiner''s route refused for another reason: ' || msg; n := n + 1; end;
  assert n = 4, 'join_pair() didn''t refuse Ryanair''s pair, a station''s, a second joiner and a joiner''s route (' || n || ' of 4)';
  -- the trigger: a row naming its own airline's route, or a joiner's route
  begin update public.routes set shares_route_id = pg_temp.sp_id('r SA1-SB2') where id = pg_temp.sp_id('r SA2-SB1');
  exception when check_violation then n := n + 1; end;
  begin update public.routes set shares_route_id = j.id where id = pg_temp.sp_id('r SB3-SA3');
  exception when check_violation then n := n + 1; end;
  assert n = 6, 'the trigger didn''t refuse a row naming its own airline''s route, or one on another pair';
  -- six pairs joined, the seventh refused inside the 14 days and allowed after them
  perform public.join_pair(pg_temp.sp_id(x)) from unnest(array['r SA1-SB2', 'r SA1-SB3', 'r SA2-SB1', 'r SA2-SB2', 'r SA2-SB3']) x;
  assert (select count(*) from public.routes ro where ro.world_id = w and ro.shares_route_id is not null) = 6, 'six pairs aren''t joined';
  begin perform public.join_pair(pg_temp.sp_id('r SA3-SB1')); exception when invalid_parameter_value then get stacked diagnostics msg = message_text;
    assert msg like '%6 pairs are joined already, the most until%', 'the seventh pair refused for another reason: ' || msg; n := n + 1; end;
  assert n = 7, 'the seventh pair wasn''t refused within 14 days of shared_pairs_from';
  update public.settings set value = to_jsonb((current_date - 14)::text) where world_id = w and airline_id is null and key = 'shared_pairs_from';
  r := public.join_pair(pg_temp.sp_id('r SA3-SB1'));
  assert (r ->> 'joined')::int = 7 and r -> 'limit' = 'null'::jsonb, 'the seventh pair wasn''t joined 14 days after shared_pairs_from: ' || r::text;
  update public.settings set value = to_jsonb(current_date::text) where world_id = w and airline_id is null and key = 'shared_pairs_from';
  raise notice 'join_pair(): JB joins SA1–SB1 with a row from SB1 to SA1 copying OA''s stars, market, distance and cabin choice, shares_route_id set, logged as claude (join_pair); refused: Ryanair''s pair, a station''s, a second joiner, a joiner''s route; the trigger refuses a row naming its own airline''s route or a joiner''s; six pairs joined, the seventh refused within 14 days of shared_pairs_from and joined after them';
end
$test$;

-- who may join: signed out and an account that isn't staff are refused; staff may
set local role anon;
do $test$
declare n int := 0;
begin
  begin perform public.join_pair(pg_temp.sp_id('r SA3-SB1')); exception when insufficient_privilege then n := n + 1; end;
  assert n = 1, 'signed out, join_pair() wasn''t refused';
end
$test$;
reset role;
do $$ begin perform set_config('request.jwt.claims',
  '{"sub": "00000000-0000-4000-8000-0000000000e1", "email": "shared-pairs-other@example.com", "role": "authenticated"}', true); end $$;
set local role authenticated;
do $test$
declare n int := 0;
begin
  begin perform public.join_pair(pg_temp.sp_id('r SA3-SB1')); exception when insufficient_privilege then n := n + 1; end;
  assert n = 1, 'an account that isn''t staff wasn''t refused join_pair()';
end
$test$;
reset role;
do $$ begin perform set_config('request.jwt.claims',
  '{"sub": "00000000-0000-4000-8000-0000000000e2", "email": "shared-pairs-staff@example.com", "role": "authenticated"}', true); end $$;
set local role authenticated;
do $test$
declare msg text;
begin
  -- staff reach the checks (this pair has a joiner) and read the view
  begin perform public.join_pair(pg_temp.sp_id('r SA3-SB1')); exception when invalid_parameter_value then get stacked diagnostics msg = message_text; end;
  assert msg like '%has a joiner already%', 'staff didn''t reach join_pair()''s checks: ' || coalesce(msg, 'no refusal');
  assert (select count(*) from public.shared_pairs p where p.world_id = pg_temp.sp_id('w') and p.joiner_route_id is not null) = 7,
    'staff don''t see the seven joined pairs in shared_pairs';
end
$test$;
reset role;
do $$ begin perform set_config('request.jwt.claims', '', true); end $$;
do $test$ begin raise notice 'signed out and an account that isn''t staff are refused join_pair(); staff reach its checks and read shared_pairs'; end $test$;

-- ---------------------------------------------------------------- 4. the ladder on SA1–SB1
do $setup$
declare w bigint := pg_temp.sp_id('w'); oa bigint := pg_temp.sp_id('oa'); jb bigint := pg_temp.sp_id('jb');
  ty bigint := pg_temp.sp_id('ty'); cy bigint := pg_temp.sp_id('cy'); run bigint; rd bigint; p jsonb; rot bigint;
begin
  -- OA flies SA1–SB1 daily at 110 both ways, every flight sold out; JB flies SB1–SA1 daily: from SB1 sold out at 200 (100%
  -- of the default, off the pair's level), from SA1 at 80% full at 220 (110%)
  perform pg_temp.sp_fly(w, oa, pg_temp.sp_id('r SA1-SB1'), 1, ty, cy, date '2029-12-01', 200, 100, 220, 100, 220);
  rot := pg_temp.sp_fly(w, jb, pg_temp.sp_id('j SB1-SA1'), 2, ty, cy, date '2029-12-01', 220, 100, 200, 80, 220);
  insert into t_sp values ('jb rot', to_jsonb(rot));
  -- OA's level: 110 both ways, stepped up on 29 Dec
  insert into public.fare_plan (world_id, airline_id, route_id, cabin_class, change_pct, fare_from, proposed_on, status, reason, level_pct, ladder_move)
  values (w, oa, pg_temp.sp_id('r SA1-SB1'), 'economy', 10, 200, date '2029-12-29', 'planned', 'test: sold out', 110, 'up');
  -- the game's default, 200 each way, read under OA only (the market pages read a pair two of our airlines fly once)
  insert into public.market_runs (world_id, started_at, finished_at, status, pages_read, pages_failed)
  values (w, timestamptz '2030-01-14 02:00:00+00', timestamptz '2030-01-14 02:15:00+00', 'done', 2, 0) returning id into run;
  for p in select x from jsonb_array_elements('[["SA1", "SB1"], ["SB1", "SA1"]]'::jsonb) x loop
    insert into public.market_reads (run_id, world_id, airline_id, origin, dest, read_at, ok)
    values (run, w, oa, p ->> 0, p ->> 1, timestamptz '2030-01-14 02:05:00+00', true) returning id into rd;
    insert into public.market_prices (read_id, world_id, airline_id, service_class, current_price, default_price) values
      (rd, w, oa, 'Y', 220, 200), (rd, w, oa, 'C', 440, 400);
  end loop;
end
$setup$;

do $test$
declare oa bigint := pg_temp.sp_id('oa'); jb bigint := pg_temp.sp_id('jb'); t timestamptz := (select (v #>> '{}')::timestamptz from t_sp where k = 't');
  d jsonb; x jsonb; st numeric; got text;
begin
  -- the owner, judged on both routes' flights
  d := private.fig_fare_ladder(oa, t);
  st := (d #>> '{settings,step_pts}')::numeric;
  x := pg_temp.sp_row(d, 'SA1', 'SB1');
  assert (x ->> 'departures')::int = 14 and (x ->> 'sold_out')::int = 7 and (x ->> 'sold_out_share')::numeric = 50 and (x ->> 'load')::numeric = 90
     and x ->> 'move' = 'down' and (x ->> 'new_level')::numeric = 110 - st and x ->> 'reason' = 'sold out 7 of 14' and (x ->> 'to_plan')::boolean,
    'OA''s SA1→SB1 isn''t judged on both airlines'' 14 flights (7 sold out: a step down): ' || coalesce(x::text, 'no row');
  x := pg_temp.sp_row(d, 'SB1', 'SA1');
  assert (x ->> 'departures')::int = 14 and (x ->> 'sold_out')::int = 14 and x ->> 'move' = 'up' and (x ->> 'new_level')::numeric = 110 + st,
    'OA''s SB1→SA1 isn''t 14 of 14 sold out, a step up: ' || coalesce(x::text, 'no row');
  assert x -> 'shared_with' = jsonb_build_object('airline_id', jb, 'airline', 'JB', 'route_id', pg_temp.sp_id('j SB1-SA1')) and x -> 'follows' = 'null'::jsonb,
    'OA''s row doesn''t name JB as shared_with: ' || coalesce(x::text, 'no row');
  assert (x ->> 'fare_index')::numeric = 110 and x ->> 'default_source' = 'market' and not (x ->> 'fix')::boolean,
    'OA''s own fares aren''t at its level 110 by the default: ' || coalesce(x::text, 'no row');
  assert (d ->> 'off_level')::int = 0 and (d ->> 'follows')::int = 0
     and (select count(*) from jsonb_array_elements(d -> 'actions') a where not (a ->> 'fix')::boolean and a ->> 'route' = 'SA1–SB1') = 2
     and not exists (select 1 from jsonb_array_elements(d -> 'actions') a where (a ->> 'fix')::boolean),
    'OA''s actions aren''t its two moves on SA1–SB1, without a set-back: ' || (d -> 'actions')::text;

  -- the joiner follows
  d := private.fig_fare_ladder(jb, t);
  assert pg_temp.sp_line(d, 'SB1', 'SA1') = '110>110 hold hold fix' and pg_temp.sp_line(d, 'SA1', 'SB1') = '110>110 hold hold ok',
    'JB''s rows don''t follow OA''s 110, with a set-back from SB1 only: ' || coalesce(pg_temp.sp_line(d, 'SB1', 'SA1'), 'no row') || ' · ' || coalesce(pg_temp.sp_line(d, 'SA1', 'SB1'), 'no row');
  x := pg_temp.sp_row(d, 'SB1', 'SA1');
  assert x -> 'follows' = jsonb_build_object('airline_id', oa, 'airline', 'OA', 'route_id', pg_temp.sp_id('r SA1-SB1'), 'hub', 'SA1', 'dest', 'SB1', 'direction', 'back')
     and x -> 'shared_with' = 'null'::jsonb and not (x ->> 'to_plan')::boolean and not (x ->> 'planned')::boolean and (x ->> 'recorded')::boolean
     and not (x ->> 'new_route')::boolean and x ->> 'reason' = 'follows OA''s ladder on SA1–SB1' and (x ->> 'departures')::int = 7,
    'JB''s SB1→SA1 row doesn''t follow OA''s SA1–SB1 back direction (its own 7 departures): ' || coalesce(x::text, 'no row');
  assert (x ->> 'fare_index')::numeric = 100 and x ->> 'default_source' = 'market' and (x ->> 'baseline_fare')::numeric = 200
     and x ->> 'fix_reason' = 'captured fare at 100%, the pair''s level 110%',
    'JB''s SB1→SA1 fares aren''t read against the default OA''s market run read (100%), set back to the pair''s 110: ' || coalesce(x::text, 'no row');
  select string_agg(format('%s>%s %s %s', a ->> 'from', a ->> 'to', a ->> 'level', case when (a ->> 'fix')::boolean then 'fix' else 'move' end), ', ' order by (a ->> 'n')::int)
    into got from jsonb_array_elements(d -> 'actions') a;
  assert got = 'SB1>SA1 110 fix', 'JB''s actions aren''t one set-back from SB1 to 110: ' || coalesce(got, 'none');
  assert (d ->> 'off_level')::int = 1 and (d ->> 'to_plan')::int = 0 and (d ->> 'follows')::int = 2
     and d -> 'moves' = '{"up": 0, "hold": 0, "down": 0, "jumps": 0, "decisions": 0}'::jsonb,
    'JB''s counts: off_level ' || (d ->> 'off_level') || ', to_plan ' || (d ->> 'to_plan') || ', follows ' || (d ->> 'follows') || ', moves ' || (d -> 'moves')::text;
  -- the fares script gets JB's set-back as any other
  assert exists (select 1 from jsonb_array_elements(private.capture_fare_actions_doc(pg_temp.sp_id('w'), t, 990602) -> 'actions') a
                  where a ->> 'route' = 'SB1–SA1' and (a ->> 'fix')::boolean),
    'the fares script''s list doesn''t carry JB''s set-back';
  raise notice 'the ladder: OA''s SA1–SB1 judged on both routes'' flights (SA1→SB1 7 of 14 sold out with JB''s, down; SB1→SA1 14 of 14, up), shared_with JB, no set-back; JB follows OA''s 110 both ways, never a move or a plan row of its own, its SB1→SA1 fares (100%% of the default read under OA) set back to the pair''s 110 as its one action, which the fares script lists';
end
$test$;

-- a frequency added by the joiner holds the pair; the joiner's route, new by its rotation, is no new route to its ladder
do $test$
declare oa bigint := pg_temp.sp_id('oa'); jb bigint := pg_temp.sp_id('jb'); t timestamptz := (select (v #>> '{}')::timestamptz from t_sp where k = 't');
  d jsonb; x jsonb;
begin
  update public.rotations set launched_on = date '2030-01-15' where id = pg_temp.sp_id('jb rot');
  d := private.fig_fare_ladder(oa, t);
  assert pg_temp.sp_line(d, 'SA1', 'SB1') = '110>110 hold hold ok' and pg_temp.sp_line(d, 'SB1', 'SA1') = '110>110 hold hold ok',
    'OA''s pair didn''t hold for JB''s new rotation: ' || coalesce(pg_temp.sp_line(d, 'SA1', 'SB1'), 'no row') || ' · ' || coalesce(pg_temp.sp_line(d, 'SB1', 'SA1'), 'no row');
  x := pg_temp.sp_row(d, 'SB1', 'SA1');
  assert x ->> 'reason' = 'a flight added on 15 Jan by JB: judged at its new size from 22 Jan' and not (x ->> 'to_plan')::boolean,
    'OA''s hold doesn''t say JB added a flight on 15 Jan: ' || coalesce(x ->> 'reason', 'none');
  d := private.fig_fare_ladder(jb, t);
  x := pg_temp.sp_row(d, 'SB1', 'SA1');
  assert not (x ->> 'new_route')::boolean and (x ->> 'fix')::boolean and x ->> 'reason' like 'follows OA''s ladder%',
    'JB''s route, new by its rotation, is read as a new route: ' || coalesce(x::text, 'no row');
  update public.rotations set launched_on = date '2029-12-01' where id = pg_temp.sp_id('jb rot');
  raise notice 'a rotation JB added on 15 Jan holds OA''s pair both ways ("a flight added on 15 Jan by JB"); JB''s route, new by that rotation, still follows and is set back, no new route';
end
$test$;

-- the owner's moves on its fare plan: the joiner's next read follows them, as set-backs
do $test$
declare w bigint := pg_temp.sp_id('w'); oa bigint := pg_temp.sp_id('oa'); jb bigint := pg_temp.sp_id('jb');
  t timestamptz := (select (v #>> '{}')::timestamptz from t_sp where k = 't'); d jsonb; x jsonb; st numeric; got text;
begin
  d := private.fig_fare_ladder(oa, t);
  st := (d #>> '{settings,step_pts}')::numeric;
  -- Put on the fare plan, as the planner writes it (model.ts planChanges): OA's two moves this Saturday
  insert into public.fare_plan (world_id, airline_id, route_id, cabin_class, change_pct, fare_from, proposed_on, status, reason, level_pct, ladder_move, direction)
  select w, oa, (e ->> 'route_id')::bigint, e ->> 'cabin', (e ->> 'change_pct')::numeric, 220, date '2030-01-19', 'planned', e ->> 'reason',
         (e ->> 'new_level')::numeric, e ->> 'ladder_kind', e ->> 'direction'
    from jsonb_array_elements(d -> 'routes') e where (e ->> 'to_plan')::boolean;
  assert (select count(*) from public.fare_plan where airline_id = oa and proposed_on = date '2030-01-19') = 2, 'OA''s two moves weren''t put on the plan';
  d := private.fig_fare_ladder(oa, t);
  assert (pg_temp.sp_row(d, 'SA1', 'SB1') ->> 'planned')::boolean and (pg_temp.sp_row(d, 'SB1', 'SA1') ->> 'planned')::boolean, 'OA''s rows aren''t planned';
  d := private.fig_fare_ladder(jb, t);
  assert pg_temp.sp_line(d, 'SA1', 'SB1') = format('110>%s down down fix', trim_scale(110 - st))
     and pg_temp.sp_line(d, 'SB1', 'SA1') = format('110>%s up up fix', trim_scale(110 + st)),
    'JB doesn''t follow OA''s planned moves with two set-backs: ' || coalesce(pg_temp.sp_line(d, 'SA1', 'SB1'), 'no row') || ' · ' || coalesce(pg_temp.sp_line(d, 'SB1', 'SA1'), 'no row');
  x := pg_temp.sp_row(d, 'SA1', 'SB1');
  assert x ->> 'reason' = format('follows OA''s ladder on SA1–SB1: on its fare plan this week at %s%%', trim_scale(110 - st))
     and x ->> 'fix_reason' = format('captured fare at 110%%, the pair''s level %s%%', trim_scale(110 - st)) and not (x ->> 'to_plan')::boolean,
    'JB''s SA1→SB1 row doesn''t say it follows OA''s plan: ' || coalesce(x::text, 'no row');
  select string_agg(format('%s>%s %s %s', a ->> 'from', a ->> 'to', a ->> 'level', case when (a ->> 'fix')::boolean then 'fix' else 'move' end), ', ' order by (a ->> 'n')::int)
    into got from jsonb_array_elements(d -> 'actions') a;
  assert got = format('SB1>SA1 %s fix, SA1>SB1 %s fix', trim_scale(110 + st), trim_scale(110 - st)),
    'JB''s actions aren''t the two set-backs to OA''s planned levels: ' || coalesce(got, 'none');
  assert d -> 'moves' = '{"up": 0, "hold": 0, "down": 0, "jumps": 0, "decisions": 0}'::jsonb and (d ->> 'off_level')::int = 2,
    'JB''s moves or off_level count its following rows: ' || (d -> 'moves')::text || ' ' || (d ->> 'off_level');
  -- the view: the pair joined and flown by both
  assert (select format('%s %s %s', p.owner_flights_week, p.joiner_flights_week, p.joined_on = (now() at time zone 'UTC')::date) from public.shared_pairs p
           where p.world_id = w and p.owner_base = 'SA1' and p.joiner_base = 'SB1') = '14 14 t',
    'shared_pairs doesn''t show SA1–SB1 flown 14 a week by each, joined today';
  raise notice 'OA''s moves put on its fare plan: JB''s next read shows the pair''s moves (down from SA1, up from SB1) and lists them as its two set-backs, nothing to plan, none counted as its moves; shared_pairs shows SA1–SB1 flown 14 a week by each, joined today';
end
$test$;

-- ---------------------------------------------------------------- 5. on the copy: its pairs, and the time
do $test$
declare x record; t0 timestamptz; ms int; before_ms int; lines text[] := '{}'; total int := 0; total_before int := 0; slowest int := 0;
  n_pairs int; n_joined int; n_unlisted int;
begin
  select count(*), count(*) filter (where p.joiner_route_id is not null), count(*) filter (where p.owner_route_id is null)
    into n_pairs, n_joined, n_unlisted
    from public.shared_pairs p where p.world_id = (select id from public.worlds where is_default);
  for x in select f.airline_id, a.iata_code from private.fig_airlines(private.fig_world(null)) f
             join public.airlines a on a.id = f.airline_id order by a.position nulls last, a.id loop
    t0 := clock_timestamp();
    perform private.fig_fare_ladder(x.airline_id, now());
    ms := round(extract(epoch from clock_timestamp() - t0) * 1000);
    before_ms := null;
    if to_regclass('rehearsal_before.fare_ladder_ms') is not null then
      execute 'select b.ms from rehearsal_before.fare_ladder_ms b where b.airline_id = $1' into before_ms using x.airline_id;
    end if;
    assert ms < 30000, format('%s: fare_ladder()''s builder took %s ms on the copy (its limit is 30 s)', x.iata_code, ms);
    assert before_ms is null or ms <= before_ms * 1.25 + 1000,
      format('%s: fare_ladder()''s builder took %s ms on the copy, %s ms before the change (more than a quarter and a second slower)', x.iata_code, ms, before_ms);
    total := total + ms; total_before := total_before + coalesce(before_ms, 0); slowest := greatest(slowest, ms);
    lines := lines || format('%s %s ms (before %s ms)', x.iata_code, ms, coalesce(before_ms::text, '—'));
  end loop;
  raise notice 'on the copy: shared_pairs lists % pair(s) of the default world, % joined, % on neither airline''s list (owner by the country rule); fare_ladder()''s builder for each of our airlines after the change (before it): %; % ms in all (% before), the slowest % ms',
    n_pairs, n_joined, n_unlisted, coalesce(array_to_string(lines, '; '), 'no airlines'), total, total_before, slowest;
end
$test$;

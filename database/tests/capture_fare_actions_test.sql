-- The fares userscript's list (spec docs/specs/2026-10-21-fares-userscript.md §1; migration
-- 20261021210000_capture_fare_actions.sql). Run by database/rehearse.sh on the copy of last night's backup, after the new
-- migrations, inside a transaction that is rolled back. A failed check stops with an error that says which (codes, ids
-- and counts of the hand-made worlds only).
-- Two worlds of their own, made inside the test around its moment (now(); the fare plan's rows of this week are dated
-- this Saturday, as Put on the fare plan dates them), each with its own capture key, every airport on UTC:
--   world 1, three active airlines of ours (in display order), one inactive and one rival's:
--     F1 (hub ZF1): ZG1 economy on the plan (+5, unseen); ZG2 economy and business on the plan to the same level (one
--        action each way, both classes); ZG3 economy on the plan and already seen in the captures (its fare 300 → 315);
--        ZG4 economy on the plan down to 95 (unseen) and business up to 105 (seen: 900 → 945); ZG5 sold out all week but
--        not on the plan; ZG6 economy on the plan and business sold out all week but not on the plan, both to 105 (one
--        action naming both classes).
--     F2 (hub ZF2, no website name): ZG7 at 105 since last week, on the plan to 110 this week (+10, unseen).
--     F3: nothing on the plan. F4, inactive, and the rival: a route each on the plan.
--   world 2, one airline of ours: a route on the plan.
--   1. Who may call capture_fare_actions(): signed out and signed in, stable, as owner with an empty search path and its
--      own 30-second statement limit, described; its builder internal, as the caller, with an empty search path.
--   2. A bad key (wrong or missing) is refused as capture_airlines() refuses it, signed out.
--   3. World 1's key, signed out: its three active airlines of ours in order with their counts, the inactive and the
--      rival's left out; only actions whose every class is on the plan this week and unseen (ZG1, ZG2, ZG4's economy and
--      ZG7), each with its game ID, name, n, from, to, sign, pct, classes and plan row ids; the seen, the unplanned and
--      the half-planned left out, though fare_ladder() lists them.
--   4. World 2's key: only its own airline; world 1's airlines left out.
--   5. On the copy: Gander with a key of its own, signed out, as the userscript calls it: every active airline of ours
--      listed, each action a whole percent with its sign and classes, and each of its plan rows on this week's fare plan
--      for that airline; how long it took (counts and milliseconds only).

create temporary table t_fa (k text primary key, v jsonb) on commit drop;
grant select, insert on t_fa to anon, authenticated;

-- a route of the airline, with n departures in the 7 days before now (out and back, 10 hours apart), each sold out in
-- economy at 300, and in business at 900 when bus is true
create function pg_temp.fa_route(w bigint, al bigint, hub text, dest text, k int, n int default 0, bus boolean default false)
returns bigint language plpgsql as $f$
declare r bigint; i int; t timestamptz;
begin
  insert into public.routes (world_id, airline_id, hub_code, dest_code, distance_km, source) values (w, al, hub, dest, 1000, 'research') returning id into r;
  for i in 0 .. n - 1 loop
    t := date_trunc('minute', now()) - interval '6 days' + make_interval(hours => i * 10);
    insert into public.game_flights (world_id, airline_id, game_date, flight_no, origin_code, dest_code, dep_local, dep_at, registration,
                                     eco_pax, eco_seats, eco_pct, eco_fare, bus_pax, bus_seats, bus_pct, bus_fare, loads_captured_at)
    values (w, al, (t at time zone 'UTC')::date, 7000 + k * 2 + i % 2, case when i % 2 = 0 then hub else dest end,
            case when i % 2 = 0 then dest else hub end, to_char(t at time zone 'UTC', 'HH24:MI'), t, 'ZQ-' || k,
            180, 180, 100, 300, case when bus then 12 end, case when bus then 12 end, case when bus then 100 end,
            case when bus then 900 end, now() - interval '1 minute');
  end loop;
  return r;
end
$f$;

-- a flight today showing the route's fares (economy, and business when given), so the fare plan sees a change in them
create function pg_temp.fa_seen(w bigint, al bigint, hub text, dest text, k int, eco_fare numeric, bus_fare numeric default null)
returns void language sql as $f$
  insert into public.game_flights (world_id, airline_id, game_date, flight_no, origin_code, dest_code, dep_local, dep_at, registration,
                                   eco_pax, eco_seats, eco_pct, eco_fare, bus_pax, bus_seats, bus_pct, bus_fare, loads_captured_at)
  values (w, al, (now() at time zone 'UTC')::date, 7900 + k, hub, dest,
          to_char((date_trunc('minute', now()) - interval '1 minute') at time zone 'UTC', 'HH24:MI'), date_trunc('minute', now()) - interval '1 minute',
          'ZQ-' || k, 150, 180, 83, eco_fare, case when bus_fare is not null then 8 end, case when bus_fare is not null then 12 end,
          case when bus_fare is not null then 67 end, bus_fare, now() - interval '30 seconds')
$f$;

-- a level recorded on the fare plan, as Put on the fare plan writes it
create function pg_temp.fa_plan(w bigint, al bigint, r bigint, cabin text, level numeric, move text, on_day date, fare_from numeric, change numeric)
returns bigint language sql as $f$
  insert into public.fare_plan (world_id, airline_id, route_id, legacy_key, cabin_class, change_pct, fare_from, proposed_on, status, reason, level_pct, ladder_move)
  values (w, al, r, 'fa-test-' || r || '-' || cabin || '-' || on_day, cabin, change, fare_from, on_day, 'planned', 'test', level, move)
  returning id
$f$;

-- ---------------------------------------------------------------- 1. who may call it
do $test$
declare f text := 'public.capture_fare_actions(text)'; g text := 'private.capture_fare_actions_doc(bigint, timestamptz)';
begin
  assert (select p.prosecdef and p.provolatile = 's' and coalesce('search_path=""' = any (p.proconfig), false)
                 and coalesce('statement_timeout=30s' = any (p.proconfig), false) from pg_proc p where p.oid = f::regprocedure),
    f || ' isn''t stable, run as owner with an empty search path and its own 30 s statement limit';
  assert has_function_privilege('anon', f, 'execute'), 'signed out (the userscript), ' || f || ' can''t be called';
  assert has_function_privilege('authenticated', f, 'execute'), 'signed in, ' || f || ' can''t be called';
  assert not exists (select 1 from pg_proc p cross join aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                      where p.oid = f::regprocedure and a.grantee = 0), f || ' is open to public';
  assert length(coalesce(obj_description(f::regprocedure, 'pg_proc'), '')) > 200, f || ' has no description';
  assert not has_function_privilege('anon', g, 'execute') and not has_function_privilege('authenticated', g, 'execute'),
    g || ' can be called from outside';
  assert (select not p.prosecdef and p.provolatile = 's' and coalesce('search_path=""' = any (p.proconfig), false) from pg_proc p where p.oid = g::regprocedure),
    g || ' runs as owner, isn''t stable or has no empty search path';
  assert obj_description(g::regprocedure, 'pg_proc') is not null, g || ' has no description';
  raise notice 'capture_fare_actions(): signed out and signed in, stable, as owner with an empty search path and a 30 s limit, described; its builder internal';
end
$test$;

-- ---------------------------------------------------------------- the hand-made worlds
do $setup$
declare
  dw bigint := (select id from public.worlds where is_default);
  v_today date := (now() at time zone 'UTC')::date;
  v_week date;
  w1 bigint; w2 bigint; g1 bigint; gr bigint; g2 bigint;
  f1 bigint; f2 bigint; f3 bigint; f4 bigint; rv bigint; o1 bigint;
  r bigint; p jsonb := '{}'::jsonb;
begin
  -- this Saturday, as the fare ladder has it: the latest Saturday on or before today (UTC)
  v_week := v_today - ((extract(isodow from v_today)::int + 1) % 7);
  perform set_config('equinox.actor', 'claude', true), set_config('equinox.actor_detail', 'capture fare actions test', true);
  insert into public.airports (code, utc_offset)
  select c, 0 from unnest(array['ZF1', 'ZF2', 'ZF3', 'ZF4', 'ZF5', 'ZG1', 'ZG2', 'ZG3', 'ZG4', 'ZG5', 'ZG6', 'ZG7', 'ZG8', 'ZG9', 'ZGA']) c
  on conflict (code) do update set utc_offset = excluded.utc_offset;
  insert into public.worlds (name, game_host, kind) values ('fare actions test', 'fare-actions.test', 'exclusive') returning id into w1;
  insert into public.worlds (name, game_host, kind) values ('fare actions other', 'fare-actions-other.test', 'exclusive') returning id into w2;
  -- each with the default world's settings and rules (the fare ladder's numbers)
  insert into public.settings (world_id, airline_id, key, value, unit, description)
  select x.id, null, s.key, s.value, s.unit, s.description from public.settings s cross join (values (w1), (w2)) x(id)
   where s.world_id = dw and s.airline_id is null;
  insert into public.world_rules (world_id, key, value, kind, unit, description)
  select x.id, wr.key, wr.value, wr.kind, wr.unit, wr.description from public.world_rules wr cross join (values (w1), (w2)) x(id)
   where wr.world_id = dw;
  insert into public.groups (world_id, name, kind) values (w1, 'ours', 'ours') returning id into g1;
  insert into public.groups (world_id, name, kind) values (w1, 'rivals', 'rival') returning id into gr;
  insert into public.groups (world_id, name, kind) values (w2, 'ours', 'ours') returning id into g2;
  -- F2 first, so display order (position) and not the id decides the order
  insert into public.airlines (world_id, group_id, game_id, planner_name, public_name, iata_code, home_airport_code, active, position)
  values (w1, g1, 990502, 'Fares Two Planner', null, 'F2', 'ZF2', true, 2) returning id into f2;
  insert into public.airlines (world_id, group_id, game_id, planner_name, public_name, iata_code, home_airport_code, active, position)
  values (w1, g1, 990501, 'Fares One Planner', 'Fares One', 'F1', 'ZF1', true, 1) returning id into f1;
  insert into public.airlines (world_id, group_id, game_id, planner_name, public_name, iata_code, home_airport_code, active, position)
  values (w1, g1, 990503, 'Fares Three Planner', 'Fares Three', 'F3', 'ZF1', true, 3) returning id into f3;
  insert into public.airlines (world_id, group_id, game_id, planner_name, public_name, iata_code, home_airport_code, active, position)
  values (w1, g1, 990504, 'Fares Off Planner', 'Fares Off', 'F4', 'ZF3', false, 4) returning id into f4;
  insert into public.airlines (world_id, group_id, game_id, game_name, active) values (w1, gr, 990509, 'Fares Rival Air', true) returning id into rv;
  insert into public.airlines (world_id, group_id, game_id, planner_name, public_name, iata_code, home_airport_code, active, position)
  values (w2, g2, 990601, 'Other World Planner', 'Other World', 'O1', 'ZF5', true, 1) returning id into o1;
  insert into public.capture_keys (label, key_hash, world_id) values
    ('capture fare actions test', extensions.crypt('fare-actions-test-key-1', extensions.gen_salt('bf')), w1),
    ('capture fare actions test, other world', extensions.crypt('fare-actions-test-key-2', extensions.gen_salt('bf')), w2);

  -- F1
  r := pg_temp.fa_route(w1, f1, 'ZF1', 'ZG1', 1);
  p := p || jsonb_build_object('zg1', pg_temp.fa_plan(w1, f1, r, 'economy', 105, 'up', v_week, 300, 5));
  r := pg_temp.fa_route(w1, f1, 'ZF1', 'ZG2', 2);
  p := p || jsonb_build_object('zg2e', pg_temp.fa_plan(w1, f1, r, 'economy', 105, 'up', v_week, 300, 5),
                               'zg2b', pg_temp.fa_plan(w1, f1, r, 'business', 105, 'up', v_week, 900, 5));
  r := pg_temp.fa_route(w1, f1, 'ZF1', 'ZG3', 3);
  perform pg_temp.fa_plan(w1, f1, r, 'economy', 105, 'up', v_week, 300, 5);
  perform pg_temp.fa_seen(w1, f1, 'ZF1', 'ZG3', 3, 315);
  r := pg_temp.fa_route(w1, f1, 'ZF1', 'ZG4', 4);
  p := p || jsonb_build_object('zg4e', pg_temp.fa_plan(w1, f1, r, 'economy', 95, 'down', v_week, 300, -5));
  perform pg_temp.fa_plan(w1, f1, r, 'business', 105, 'up', v_week, 900, 5);
  perform pg_temp.fa_seen(w1, f1, 'ZF1', 'ZG4', 4, 300, 945);
  r := pg_temp.fa_route(w1, f1, 'ZF1', 'ZG5', 5, 14);
  r := pg_temp.fa_route(w1, f1, 'ZF1', 'ZG6', 6, 14, true);
  perform pg_temp.fa_plan(w1, f1, r, 'economy', 105, 'up', v_week, 300, 5);
  -- F2: last week's level, then this week's move
  r := pg_temp.fa_route(w1, f2, 'ZF2', 'ZG7', 7);
  perform pg_temp.fa_plan(w1, f2, r, 'economy', 105, 'up', v_week - 7, 300, 5);
  p := p || jsonb_build_object('zg7', pg_temp.fa_plan(w1, f2, r, 'economy', 110, 'up', v_week, 315, 4.8));
  -- F4 (inactive), the rival, and world 2's airline
  r := pg_temp.fa_route(w1, f4, 'ZF3', 'ZG8', 8);
  perform pg_temp.fa_plan(w1, f4, r, 'economy', 105, 'up', v_week, 300, 5);
  r := pg_temp.fa_route(w1, rv, 'ZF4', 'ZG9', 9);
  perform pg_temp.fa_plan(w1, rv, r, 'economy', 105, 'up', v_week, 300, 5);
  r := pg_temp.fa_route(w2, o1, 'ZF5', 'ZGA', 10);
  p := p || jsonb_build_object('zga', pg_temp.fa_plan(w2, o1, r, 'economy', 105, 'up', v_week, 300, 5));

  perform set_config('equinox.actor', '', true), set_config('equinox.actor_detail', '', true);
  insert into t_fa values ('plans', p), ('f1', to_jsonb(f1)), ('f4', to_jsonb(f4)), ('rv', to_jsonb(rv)), ('week', to_jsonb(v_week));
end
$setup$;

-- the setup as the fare ladder sees it: F1's 14 actions (the 7 routes' moves, both ways), F4's and the rival's 2 each,
-- so what capture_fare_actions() leaves out is its own doing
do $test$
declare f1 bigint := (select (v #>> '{}')::bigint from t_fa where k = 'f1'); f4 bigint := (select (v #>> '{}')::bigint from t_fa where k = 'f4');
  rv bigint := (select (v #>> '{}')::bigint from t_fa where k = 'rv'); d jsonb; got text;
begin
  d := private.fig_fare_ladder(f1, now());
  select string_agg((x ->> 'n') || ' ' || (x ->> 'from') || '>' || (x ->> 'to') || ' ' || (x ->> 'sign') || (x ->> 'pct') || ' '
                    || (select string_agg(c, ',') from jsonb_array_elements_text(x -> 'classes') c), ' | ' order by (x ->> 'n')::int)
    into got from jsonb_array_elements(d -> 'actions') x;
  assert got = '1 ZF1>ZG1 +5 economy | 2 ZG1>ZF1 +5 economy | 3 ZF1>ZG2 +5 economy,business | 4 ZG2>ZF1 +5 economy,business | '
            || '5 ZF1>ZG3 +5 economy | 6 ZG3>ZF1 +5 economy | 7 ZF1>ZG4 -5 economy | 8 ZG4>ZF1 -5 economy | '
            || '9 ZF1>ZG4 +5 business | 10 ZG4>ZF1 +5 business | 11 ZF1>ZG5 +5 economy | 12 ZG5>ZF1 +5 economy | '
            || '13 ZF1>ZG6 +5 economy,business | 14 ZG6>ZF1 +5 economy,business',
    'the hand-made F1 isn''t as the fare ladder should see it: ' || coalesce(got, 'no actions');
  select string_agg((x ->> 'dest') || ' ' || (x ->> 'cabin') || ' ' || (x ->> 'planned') || ' ' || (x ->> 'applied'), ', ' order by x ->> 'dest', x ->> 'cabin')
    into got from jsonb_array_elements(d -> 'routes') x where x ->> 'dest' in ('ZG3', 'ZG4', 'ZG5', 'ZG6');
  assert got = 'ZG3 economy true true, ZG4 business true true, ZG4 economy true false, ZG5 economy false false, ZG6 business false false, ZG6 economy true false',
    'the hand-made F1''s routes aren''t planned and seen as meant: ' || coalesce(got, 'none');
  assert jsonb_array_length(private.fig_fare_ladder(f4, now()) -> 'actions') = 2 and jsonb_array_length(private.fig_fare_ladder(rv, now()) -> 'actions') = 2,
    'the inactive airline and the rival haven''t their 2 actions each';
  raise notice 'the hand-made world as the fare ladder sees it: F1 14 actions (ZG3 seen, ZG4 business seen, ZG5 not planned, ZG6 business not planned), F4 and the rival 2 each';
end
$test$;

-- ---------------------------------------------------------------- 2 to 4, signed out like the userscript
set local role anon;
do $test$
declare r jsonb; got text;
begin
  -- 2. a bad key
  r := public.capture_fare_actions('not the key');
  assert r = '{"ok": false, "error": "bad key"}'::jsonb, 'a wrong key wasn''t refused as capture_airlines() refuses it: ' || r::text;
  r := public.capture_fare_actions(null);
  assert r = '{"ok": false, "error": "bad key"}'::jsonb, 'a missing key wasn''t refused: ' || r::text;

  -- 3. world 1
  r := public.capture_fare_actions('fare-actions-test-key-1');
  insert into t_fa values ('w1', r);
  assert r ->> 'ok' = 'true' and r ->> 'world' = 'fare actions test' and r ->> 'week_of' = (select v #>> '{}' from t_fa where k = 'week'),
    'world 1''s key didn''t answer for its world and this Saturday: ' || jsonb_build_object('ok', r -> 'ok', 'world', r -> 'world', 'week_of', r -> 'week_of')::text;
  select string_agg((a ->> 'game_id') || ' ' || (a ->> 'name') || ' ' || (a ->> 'code') || ' ' || (a ->> 'count'), ' | ' order by i)
    into got from jsonb_array_elements(r -> 'airlines') with ordinality as t(a, i);
  assert got = '990501 Fares One F1 6 | 990502 Fares Two Planner F2 2 | 990503 Fares Three F3 0',
    'world 1''s airlines (in order, the inactive and the rival''s left out) are ' || coalesce(got, 'none');
  select string_agg((x ->> 'game_id') || ' ' || (x ->> 'airline') || ' ' || (x ->> 'n') || ' ' || (x ->> 'route') || ' ' || (x ->> 'from') || '>'
                    || (x ->> 'to') || ' ' || (x ->> 'sign') || (x ->> 'pct') || ' ' || (x ->> 'level') || ' '
                    || (select string_agg(c, ',') from jsonb_array_elements_text(x -> 'classes') c), ' | ' order by i)
    into got from jsonb_array_elements(r -> 'actions') with ordinality as t(x, i);
  assert got = '990501 Fares One 1 ZF1–ZG1 ZF1>ZG1 +5 105 economy | 990501 Fares One 2 ZF1–ZG1 ZG1>ZF1 +5 105 economy | '
            || '990501 Fares One 3 ZF1–ZG2 ZF1>ZG2 +5 105 economy,business | 990501 Fares One 4 ZF1–ZG2 ZG2>ZF1 +5 105 economy,business | '
            || '990501 Fares One 7 ZF1–ZG4 ZF1>ZG4 -5 95 economy | 990501 Fares One 8 ZF1–ZG4 ZG4>ZF1 -5 95 economy | '
            || '990502 Fares Two Planner 1 ZF2–ZG7 ZF2>ZG7 +10 110 economy | 990502 Fares Two Planner 2 ZF2–ZG7 ZG7>ZF2 +10 110 economy',
    'world 1''s actions (only every class planned and unseen) are ' || coalesce(got, 'none');
  assert not exists (select 1 from jsonb_array_elements(r -> 'actions') x
                      where jsonb_typeof(x -> 'pct') <> 'number' or jsonb_typeof(x -> 'game_id') <> 'number' or x ->> 'text' not like 'From %'),
    'an action''s pct or game ID isn''t a number, or it has no words';

  -- 4. world 2
  r := public.capture_fare_actions('fare-actions-test-key-2');
  select string_agg((a ->> 'game_id') || ' ' || (a ->> 'count'), ' | ') into got from jsonb_array_elements(r -> 'airlines') a;
  assert r ->> 'world' = 'fare actions other' and got = '990601 2'
     and (select bool_and(x ->> 'game_id' = '990601' and x ->> 'route' = 'ZF5–ZGA') from jsonb_array_elements(r -> 'actions') x)
     and jsonb_array_length(r -> 'actions') = 2,
    'world 2''s key didn''t give only its own airline''s 2 actions: ' || coalesce(got, 'none');
  insert into t_fa values ('w2', r);
end
$test$;
reset role;

-- each kept action's plan rows: one per class, in the class order, the rows of this week's fare plan
do $test$
declare p jsonb := (select v from t_fa where k = 'plans'); r jsonb := (select v from t_fa where k = 'w1'); got text;
begin
  select string_agg((x ->> 'from') || '>' || (x ->> 'to') || ' ' || (x -> 'plan_ids')::text, ' | ' order by i)
    into got from jsonb_array_elements(r -> 'actions') with ordinality as t(x, i);
  assert got = format('ZF1>ZG1 [%s] | ZG1>ZF1 [%s] | ZF1>ZG2 [%s, %s] | ZG2>ZF1 [%s, %s] | ZF1>ZG4 [%s] | ZG4>ZF1 [%s] | ZF2>ZG7 [%s] | ZG7>ZF2 [%s]',
                      p ->> 'zg1', p ->> 'zg1', p ->> 'zg2e', p ->> 'zg2b', p ->> 'zg2e', p ->> 'zg2b', p ->> 'zg4e', p ->> 'zg4e', p ->> 'zg7', p ->> 'zg7'),
    'the actions'' plan rows are ' || coalesce(got, 'none');
  assert (select v -> 'actions' -> 0 -> 'plan_ids' from t_fa where k = 'w2') = jsonb_build_array((p ->> 'zga')::bigint),
    'world 2''s action doesn''t name its plan row';
  raise notice 'world 1: F1 (6 actions: ZG1 and ZG2 both ways, ZG2 with both classes, ZG4''s economy −5), F2 (2: ZG7 +10), F3 (0), each with its plan rows; the seen (ZG3, ZG4 business), the unplanned (ZG5) and the half-planned (ZG6) left out, the inactive airline and the rival not listed; world 2 only its own airline';
end
$test$;

-- ---------------------------------------------------------------- 5. on the copy: Gander, as the userscript calls it
do $setup$
begin
  insert into public.capture_keys (label, key_hash, world_id)
  select 'capture fare actions test, Gander', extensions.crypt('fare-actions-gander-key', extensions.gen_salt('bf')), w.id
    from public.worlds w where w.is_default;
end
$setup$;

set local role anon;
do $test$
declare t0 timestamptz := clock_timestamp(); r jsonb;
begin
  r := public.capture_fare_actions('fare-actions-gander-key');
  insert into t_fa values ('gander', r), ('gander_ms', to_jsonb(round(extract(epoch from clock_timestamp() - t0) * 1000)));
end
$test$;
reset role;

do $test$
declare r jsonb := (select v from t_fa where k = 'gander'); ms numeric := (select (v #>> '{}')::numeric from t_fa where k = 'gander_ms');
  dw bigint := (select id from public.worlds where is_default); bad text; n_ours int;
  v_today date := (now() at time zone 'UTC')::date; v_week date;
begin
  v_week := v_today - ((extract(isodow from v_today)::int + 1) % 7);
  assert r ->> 'ok' = 'true' and r ->> 'world' = (select name from public.worlds where id = dw), 'Gander''s key didn''t answer for Gander: ' || coalesce(r ->> 'error', 'no error');
  select count(*) into n_ours from public.airlines a join public.groups g on g.id = a.group_id and g.world_id = a.world_id
   where a.world_id = dw and a.active and g.kind = 'ours';
  assert jsonb_array_length(r -> 'airlines') = n_ours, format('Gander lists %s airlines, not its %s active ones of ours', jsonb_array_length(r -> 'airlines'), n_ours);
  assert (select coalesce(sum((a ->> 'count')::int), 0) from jsonb_array_elements(r -> 'airlines') a) = jsonb_array_length(r -> 'actions'),
    'the airlines'' counts don''t add up to the actions';
  -- each action as the userscript needs it: a sign, a whole percent from 0 to 100, one or two known classes, an airport each end
  select string_agg(x ->> 'game_id' || ' ' || (x ->> 'n'), ', ') into bad from jsonb_array_elements(r -> 'actions') x
   where x ->> 'sign' not in ('+', '-') or jsonb_typeof(x -> 'pct') <> 'number' or (x ->> 'pct')::numeric <> trunc((x ->> 'pct')::numeric)
      or (x ->> 'pct')::numeric not between 0 and 100 or jsonb_array_length(x -> 'classes') not in (1, 2)
      or exists (select 1 from jsonb_array_elements_text(x -> 'classes') c where c not in ('economy', 'business'))
      or jsonb_array_length(x -> 'plan_ids') <> jsonb_array_length(x -> 'classes')
      or coalesce(x ->> 'from', '') !~ '^[A-Z0-9]{3}$' or coalesce(x ->> 'to', '') !~ '^[A-Z0-9]{3}$' or x ->> 'from' = x ->> 'to';
  assert bad is null, 'actions the userscript couldn''t make (game ID and n): ' || bad;
  -- each plan row a ladder row of this week's fare plan, of that airline, in the class it names
  select string_agg(x ->> 'game_id' || ' ' || (x ->> 'n'), ', ') into bad
    from jsonb_array_elements(r -> 'actions') x
    cross join lateral jsonb_array_elements_text(x -> 'classes') with ordinality as c(cabin, k)
   where not exists (select 1 from public.fare_plan fp join public.airlines a on a.id = fp.airline_id
                      where fp.id = (x -> 'plan_ids' ->> (c.k::int - 1))::bigint and a.world_id = dw and a.game_id = (x ->> 'game_id')::int
                        and fp.status = 'planned' and fp.level_pct is not null and fp.proposed_on >= v_week and coalesce(fp.cabin_class, 'economy') = c.cabin);
  assert bad is null, 'actions whose plan rows aren''t this week''s for that airline and class (game ID and n): ' || bad;
  raise notice 'on the copy, signed out: % airlines, % changes still to make this week, in % ms (the call''s own limit is 30 s; signed out the role''s is 3 s)',
    jsonb_array_length(r -> 'airlines'), jsonb_array_length(r -> 'actions'), ms;
end
$test$;

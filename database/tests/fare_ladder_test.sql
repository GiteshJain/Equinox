-- The fare ladder (manual §5; migrations 20261021120000_fare_ladder.sql, 20261021190000_fare_actions_by_route.sql,
-- 20261021230000_frequencies_and_fares.sql and 20261021235000_competition.sql; specs docs/specs/2026-10-21-fare-ladder.md,
-- docs/specs/2026-10-21-fare-actions-by-route.md, docs/specs/2026-10-21-frequencies-and-fares.md and
-- docs/specs/2026-10-21-competition-analysis.md §2). Run by
-- database/rehearse.sh on the copy of last night's backup, after the new migrations, inside a transaction that is rolled
-- back. A failed check stops with an error that says which (codes, levels, moves and words of the hand-made routes only).
-- Everything is made in a world of its own, so nothing on the copy is touched or counted.
--   The moment T is Saturday 19 Jan 2030, 12:00 UTC: the week is the 7 days before it. Each route flies 14 departures in
--   it (out and back, daily), each one's economy load 100% (sold out) or 80%, its fare 300 unless said; every airport is
--   on UTC. A route launched before the week also has an out and back the day after it launched at its launch level's
--   fare (the fare index's baseline: its first captured fare, since it launched after 21 Oct 2026). Six of our airlines:
--     L1 (launch 100%; bases ZA1 then ZA2, economy only): ZA1 to ZB1, ZB2, ZB3, ZB4 sold out 14 of 14 (up to 105); ZB5 13
--        of 14 (hold); ZB6 at 110% since 12 Jan, 10 of 14 (down to 105; its fares at 100%, so it is set back to 110 first);
--        ZA1–ZA2 14 of 14 (up: a route between two of its bases); ZA2 to ZC1 14 of 14 (up), ZC2, ZC3, ZC4 13 of 14 (hold).
--        So 6 up, 4 hold, 1 down, and the game actions route by route only (since 21 Oct: never a whole base): ZB6's two
--        set-back changes first, then each of the 7 routes that move, From hub to dest then From dest to hub, economy; the 4
--        that hold get none.
--     L2 (launch 85%, as Ryanair; economy only): ZS1 up to 90; ZS2 at 105 capped; ZS3 at 102 up to the 105 cap; ZS4 at 90
--        since 12 Jan (a ladder row: fare 85 → 88 on 13 Jan, 90 from 14 Jan) up to 95. Capped ZS2 gets no action.
--     L3 (launch 55%): ZU1 and ZU2 flown by a rival in the latest scan, ZU5 by L4 (our own airline): 62 down to the 60%
--        floor, 60 holds at it, 62 down to 60; ZU3 at 60 down to 55 (launch), ZU4 at launch holds; all 10 of 14.
--     L4 (launch 100%; business seats): ZE1 at 120 in economy (capped) while business climbs from 100 (each cabin on its
--        own); ZE2 stepped down on 12 Jan (held, with a hold to record); ZE3 stepped down on 5 Jan (two weeks: climbs
--        again); ZE4 launched 15 Jan (new: holds); ZE5 only 4 departures (holds); ZE6 up already on the fare plan this
--        Saturday; ZE7 at 105 since 12 Jan with its fare 300 → 315 (index 105, matches); ZE8 a business ladder row from 900
--        (930 on 13 Jan, 945 from 15 Jan); ZE9 sold out in both cabins, both up from 100 to 105 (one action each way with
--        both classes); ZEA economy at 105 since 12 Jan up to 110 and business up from 100 to 105 (different levels: one
--        action each way for each cabin). Every fare at its level: no set-back changes.
--     L5 (launch 100%; business seats), new frequencies and set-back changes: ZK2 gained a rotation on 16 Jan (holds:
--        "a flight added on 16 Jan: judged at its new size from 23 Jan"; with it launched 11 Jan, 8 days before, it moves);
--        ZK3's only rotation launched 16 Jan (a new route); ZK4 at 110 with its fares at 100% and a move on the fare plan
--        this Saturday (no set-back); ZK5 at launch with four flights on the latest day, one of them at 98% (set back:
--        each flight compared, though the day's average, 99.5, is within a point); ZK6 launched 15 Jan with a flight at
--        110% (new: no set-back); ZK7 at 110 in both cabins with both at 100% (set back, one action each way naming both
--        classes); ZK8 at 110 with its fares at 100% and a rotation launched 18 Jan, its latest captured day (holds, and
--        no set-back until a capture after it); ZKA launched 1 Nov, its business first captured in the week (the days
--        before archived: no business index), its economy's baseline from the daily history (route_days).
--     L6 (launch 85%, as Ryanair): ZW1 launched 30 Sep 2026 at the default price (300) and cut to 85% (255) on 5 Oct, like
--        Ryanair's four early cuts: its baseline is its fare on 20 Oct 2026, the latest captured day on or before 21 Oct,
--        so its index is 85 (the first fare would make it 72); ZW2 with no flights on or before 21 Oct but the daily
--        history's economy fare that day (255): index 85.
--     L7 (launch 100%), the rival pause (competition analysis, spec §2): every route sold out 14 of 14. The world's finished
--        scans are 4, 11, 16 and 17 Jan (and one still running on 18 Jan); Quest Air, a rival, flies L7's pairs: ZQ1 started
--        on 16 Jan (paused: "rival Quest Air started here on 16 Jan: paused until 23 Jan"); ZQ2 7 → 14 on 16 Jan (paused,
--        "added 7 a week"); ZQ3 7 → 10 (3 added, under competition_threat_min_weekly: moves up); ZQ4 started on 11 Jan, more
--        than 7 days before (no longer paused: moves up); ZQ5 started on 16 Jan with a flight added on 16 Jan too (added
--        comes first). L3's rival flies ZU1 and ZU2 in every one of them, so it never started there.
--   1. The seven settings, in every world, described; fare_plan's two new columns described, and a move it doesn't know refused.
--   2. Who may call fare_ladder(): signed in only, stable, as owner with an empty search path, described; its builder internal.
--   3. L5, a new frequency holds the route for a week (spec part 1): after planned, new and few; the same route 8 days on
--      moves; a route whose only rotation is new is still "new route".
--   4. L5 and L6, the set-back changes and the fare index (spec part 3): none for a route on the fare plan this week, a new
--      route, or one not captured since its newest rotation launched; each flight compared; both classes in one action;
--      the 21 Oct baseline (Ryanair's early cuts), the daily history's, and no business index once its first days are
--      archived. (L1's ZB6, below, is the route at 100% against 110% with its two fix actions at +10%.)
--   5. L1: each move, level and reason; the counts; what Put on the fare plan writes; the game actions route by route, in
--      order, with no base action (a route between two bases is a route like any other); ZB6 set back first.
--   6. L2: Ryanair's 85% launch, the cap at 105% and a step up to the cap; a capped route gets no action.
--   7. L3: the 60% floor where another player flies the pair (a rival in the scan, or our own airline), and the launch floor.
--   8. L4: the cap, each cabin on its own, the 2-week hold after a step down and after it, a new route, too few departures,
--      a move already on the fare plan this Saturday, and the fare index. The game actions: one cabin moving (economy or
--      business), both cabins to the same level (both classes in one action each way) and to different levels (one
--      action each way per cabin); a held, new, capped or few-departures route never listed; no set-back.
--   9. fare_plan_status(): a ladder row is seen when the fare moves by its ratio within 1% (not at half the change), in its
--      own cabin.
--  10. Signed out and an account that isn't staff are refused; staff get what postgres gets.
--  11. L7: the rival pause (spec §2): a rival that started or added competition_threat_min_weekly a week in a scan of the
--      last 7 days holds the route with its reason, after added and before the sold-out share; one under the threshold or
--      older than 7 days doesn't; nothing to put on the fare plan and no game action for a paused route.
-- The routes off their level on the copy, before and after the new index, are counted in frequencies_and_fares_test.sql.

create temporary table t_fl (k text primary key, v jsonb) on commit drop;
grant select, insert, update on t_fl to authenticated, anon;
insert into public.planner_users (email) values ('fare-ladder-staff@example.com') on conflict do nothing;

-- one route: its rotation, an aircraft, its two legs and n departures in the week, the first `sold` of them sold out in
-- economy (and the first `bus_sold` in business when given). A route launched before the week also gets an out and back
-- the day after it launched, at `base` in economy (and `bus_base` in business): its first captured fares, the fare index's
-- baseline (spec docs/specs/2026-10-21-frequencies-and-fares.md §3), unless with_base is false.
create function pg_temp.ladder_route(w bigint, al bigint, hub text, dest text, k int, n int, sold int, launched date, ty bigint,
                                     cfg bigint, fare numeric default 300, bus_sold int default null, bus_fare numeric default 900,
                                     base numeric default 300, bus_base numeric default 900, with_base boolean default true)
returns bigint language plpgsql as $f$
declare r bigint; rot bigint; ac bigint; i int; t timestamptz;
begin
  insert into public.routes (world_id, airline_id, hub_code, dest_code, distance_km, source) values (w, al, hub, dest, 1000, 'research') returning id into r;
  insert into public.rotations (world_id, airline_id, route_id, launched_on) values (w, al, r, launched) returning id into rot;
  insert into public.aircraft (world_id, airline_id, registration, aircraft_type_id, cabin_config_id, status, base_code)
  values (w, al, 'ZL-' || k, ty, cfg, 'active', hub) returning id into ac;
  insert into public.flight_legs (world_id, airline_id, rotation_id, leg_no, flight_no, origin_code, dest_code, aircraft_id, days_utc, dep_utc_min, block_min) values
    (w, al, rot, 1, 5000 + k * 2, hub, dest, ac, '{1,2,3,4,5,6,7}', 840, 60),
    (w, al, rot, 2, 5001 + k * 2, dest, hub, ac, '{1,2,3,4,5,6,7}', 1080, 60);
  if with_base and launched + 1 < date '2030-01-12' then
    for i in 0 .. 1 loop
      t := (launched + 1)::timestamp at time zone 'UTC' + make_interval(hours => 14 + i * 4);
      insert into public.game_flights (world_id, airline_id, game_date, flight_no, origin_code, dest_code, dep_local, dep_at, registration,
                                       eco_pax, eco_seats, eco_pct, eco_fare, bus_pax, bus_seats, bus_pct, bus_fare, loads_captured_at)
      values (w, al, launched + 1, 5000 + k * 2 + i, case when i = 0 then hub else dest end, case when i = 0 then dest else hub end,
              to_char(t at time zone 'UTC', 'HH24:MI'), t, 'ZL-' || k, 180, 180, 100, base,
              case when bus_sold is not null then 12 end, case when bus_sold is not null then 12 end, case when bus_sold is not null then 100 end,
              case when bus_sold is not null then bus_base end, t + interval '1 day');
    end loop;
  end if;
  for i in 0 .. n - 1 loop
    -- from 12 Jan 14:00 (inside the week) a day at a time, the return 4 hours after its outbound
    t := timestamptz '2030-01-12 14:00:00+00' + make_interval(days => i / 2, hours => (i % 2) * 4);
    insert into public.game_flights (world_id, airline_id, game_date, flight_no, origin_code, dest_code, dep_local, dep_at, registration,
                                     eco_pax, eco_seats, eco_pct, eco_fare, bus_pax, bus_seats, bus_pct, bus_fare, loads_captured_at)
    values (w, al, (t at time zone 'UTC')::date, 5000 + k * 2 + i % 2, case when i % 2 = 0 then hub else dest end,
            case when i % 2 = 0 then dest else hub end, to_char(t at time zone 'UTC', 'HH24:MI'), t, 'ZL-' || k,
            case when i < sold then 180 else 144 end, 180, case when i < sold then 100 else 80 end, fare,
            case when bus_sold is null then null when i < bus_sold then 12 else 8 end, case when bus_sold is null then null else 12 end,
            case when bus_sold is null then null when i < bus_sold then 100 else 70 end, case when bus_sold is null then null else bus_fare end,
            timestamptz '2030-01-19 11:00:00+00');
  end loop;
  return r;
end
$f$;

-- a route's out and back on a day, at a fare in economy, captured the day after
create function pg_temp.ladder_day(w bigint, al bigint, hub text, dest text, k int, on_day date, fare numeric)
returns void language sql as $f$
  insert into public.game_flights (world_id, airline_id, game_date, flight_no, origin_code, dest_code, dep_local, dep_at, registration,
                                   eco_pax, eco_seats, eco_pct, eco_fare, loads_captured_at)
  select w, al, on_day, 5000 + k * 2 + i, case when i = 0 then hub else dest end, case when i = 0 then dest else hub end,
         case when i = 0 then '14:00' else '18:00' end, on_day::timestamp at time zone 'UTC' + make_interval(hours => 14 + i * 4),
         'ZL-' || k, 180, 180, 100, fare, (on_day + 1)::timestamp at time zone 'UTC'
    from generate_series(0, 1) i
$f$;

-- the daily history's economy fare on a day (route_days), both ways
create function pg_temp.ladder_history(w bigint, al bigint, r bigint, hub text, dest text, on_day date, fare numeric)
returns void language sql as $f$
  insert into public.route_days (world_id, airline_id, route_id, origin_code, dest_code, day, flights, passengers, seats, eco_fare_avg)
  values (w, al, r, hub, dest, on_day, 1, 180, 180, fare), (w, al, r, dest, hub, on_day, 1, 180, 180, fare)
$f$;

-- a level recorded on the fare plan
create function pg_temp.ladder_row(w bigint, al bigint, r bigint, cabin text, level numeric, move text, on_day date, fare_from numeric default null,
                                   change numeric default null)
returns bigint language sql as $f$
  insert into public.fare_plan (world_id, airline_id, route_id, legacy_key, cabin_class, change_pct, fare_from, proposed_on, status, reason, level_pct, ladder_move)
  values (w, al, r, 'fl-test-' || r || '-' || cabin || '-' || on_day, cabin, change, fare_from, on_day, 'planned', 'test', level, move)
  returning id
$f$;

-- ---------------------------------------------------------------- 1. the settings and the fare plan's columns
do $test$
declare n_worlds int := (select count(*) from public.worlds); bad text;
begin
  select string_agg(k.key, ', ') into bad
    from (values ('fare_ladder_step_pts', 5), ('fare_ladder_up_share', 100), ('fare_ladder_down_share', 90),
                 ('fare_ladder_min_departures', 5), ('fare_ladder_hold_weeks', 2), ('fare_ladder_cap_pts', 20),
                 ('fare_ladder_capacity_hold_days', 7)) k(key, v)
   where (select count(*) from public.settings s where s.key = k.key and s.airline_id is null and s.value = to_jsonb(k.v)
            and length(coalesce(s.description, '')) > 40 and s.unit is not null and s.since = date '2026-10-21' and s.reason is not null) <> n_worlds;
  assert bad is null, 'not in every world with its value, unit, description, date and reason: ' || bad;
  assert col_description('public.fare_plan'::regclass, (select attnum from pg_attribute where attrelid = 'public.fare_plan'::regclass and attname = 'level_pct')) like '%default price%'
     and col_description('public.fare_plan'::regclass, (select attnum from pg_attribute where attrelid = 'public.fare_plan'::regclass and attname = 'ladder_move')) like '%up, down or hold%',
    'fare_plan.level_pct or ladder_move has no description';
  assert (select format_type(atttypid, atttypmod) from pg_attribute where attrelid = 'public.fare_plan'::regclass and attname = 'level_pct') = 'numeric(5,1)',
    'fare_plan.level_pct isn''t numeric(5,1)';
  begin
    insert into public.fare_plan (world_id, airline_id, status, ladder_move)
    select a.world_id, a.id, 'planned', 'sideways' from public.airlines a join public.worlds w on w.id = a.world_id and w.is_default limit 1;
    assert false, 'fare_plan took a ladder move that isn''t up, down or hold';
  exception when check_violation then null;
  end;
  assert (select s.description like '%taken away isn''t tracked%' and s.unit = 'days' from public.settings s
           where s.key = 'fare_ladder_capacity_hold_days' and s.airline_id is null order by s.world_id limit 1),
    'fare_ladder_capacity_hold_days doesn''t say a frequency taken away isn''t tracked, or isn''t in days';
  raise notice 'the seven fare ladder settings in each of the % world(s) (5 points, up at 100%%, down under 90%%, 5 departures, 2 weeks, cap 20 points, a new flight held 7 days), described; fare_plan.level_pct numeric(5,1) and ladder_move (up, down or hold) described', n_worlds;
end
$test$;

-- ---------------------------------------------------------------- 2. who may call fare_ladder()
do $test$
declare f text := 'public.fare_ladder(bigint, timestamptz)'; g text := 'private.fig_fare_ladder(bigint, timestamptz)';
begin
  assert (select p.prosecdef and p.provolatile = 's' and coalesce('search_path=""' = any (p.proconfig), false) from pg_proc p where p.oid = f::regprocedure),
    f || ' isn''t stable, run as owner with an empty search path';
  assert not has_function_privilege('anon', f, 'execute'), 'signed out, ' || f || ' can be called';
  assert has_function_privilege('authenticated', f, 'execute'), 'signed in, ' || f || ' can''t be called';
  assert length(coalesce(obj_description(f::regprocedure, 'pg_proc'), '')) > 100, f || ' has no description';
  assert not has_function_privilege('authenticated', g, 'execute') and not has_function_privilege('anon', g, 'execute'), g || ' can be called from outside';
  assert (select not p.prosecdef and p.provolatile = 's' and coalesce('search_path=""' = any (p.proconfig), false) from pg_proc p where p.oid = g::regprocedure),
    g || ' runs as owner, isn''t stable or has no empty search path';
  assert obj_description(g::regprocedure, 'pg_proc') is not null, g || ' has no description';
  raise notice 'fare_ladder(): signed in only, stable, as owner with an empty search path, described; its builder internal';
end
$test$;

-- ---------------------------------------------------------------- the hand-made world
do $setup$
declare
  dw bigint := (select id from public.worlds where is_default);
  w bigint; g bigint; gr bigint; l1 bigint; l2 bigint; l3 bigint; l4 bigint; l5 bigint; l6 bigint; l7 bigint; rv bigint; rq bigint;
  ty bigint; cy bigint; cj bigint;
  sc bigint; r bigint; rot bigint; x record;
begin
  perform set_config('equinox.actor', 'claude', true), set_config('equinox.actor_detail', 'fare ladder test', true);
  insert into public.airports (code, utc_offset)
  select c, 0 from unnest(array['ZA1', 'ZA2', 'ZB1', 'ZB2', 'ZB3', 'ZB4', 'ZB5', 'ZB6', 'ZC1', 'ZC2', 'ZC3', 'ZC4', 'ZR1', 'ZS1', 'ZS2', 'ZS3', 'ZS4',
                                'ZT1', 'ZU1', 'ZU2', 'ZU3', 'ZU4', 'ZU5', 'ZD1', 'ZE1', 'ZE2', 'ZE3', 'ZE4', 'ZE5', 'ZE6', 'ZE7', 'ZE8',
                                'ZE9', 'ZEA', 'ZK1', 'ZK2', 'ZK3', 'ZK4', 'ZK5', 'ZK6', 'ZK7', 'ZK8', 'ZKA', 'ZW0', 'ZW1', 'ZW2',
                                'ZQ0', 'ZQ1', 'ZQ2', 'ZQ3', 'ZQ4', 'ZQ5']) c
  on conflict (code) do update set utc_offset = excluded.utc_offset;
  insert into public.worlds (name, game_host, kind) values ('fare ladder test', 'fare-ladder.test', 'exclusive') returning id into w;
  insert into public.settings (world_id, airline_id, key, value, unit, description)
  select w, null, s.key, s.value, s.unit, s.description from public.settings s where s.world_id = dw and s.airline_id is null;
  insert into public.world_rules (world_id, key, value, kind, unit, description)
  select w, r2.key, r2.value, r2.kind, r2.unit, r2.description from public.world_rules r2 where r2.world_id = dw;
  update public.world_rules set value = '60'::jsonb where world_id = w and key = 'fare_floor_pct';
  insert into public.groups (world_id, name, kind) values (w, 'ours', 'ours') returning id into g;
  insert into public.groups (world_id, name, kind) values (w, 'rivals', 'rival') returning id into gr;
  insert into public.airlines (world_id, group_id, game_id, planner_name, public_name, iata_code, home_airport_code, active, position) values
    (w, g, 990301, 'Ladder One', 'L One', 'L1', 'ZA1', true, 1),
    (w, g, 990302, 'Ladder Two', 'L Two', 'L2', 'ZR1', true, 2),
    (w, g, 990303, 'Ladder Three', 'L Three', 'L3', 'ZT1', true, 3),
    (w, g, 990304, 'Ladder Four', 'L Four', 'L4', 'ZD1', true, 4),
    (w, g, 990305, 'Ladder Five', 'L Five', 'L5', 'ZK1', true, 5),
    (w, g, 990306, 'Ladder Six', 'L Six', 'L6', 'ZW0', true, 6),
    (w, g, 990307, 'Ladder Seven', 'L Seven', 'L7', 'ZQ0', true, 7);
  select id into l1 from public.airlines where world_id = w and iata_code = 'L1';
  select id into l2 from public.airlines where world_id = w and iata_code = 'L2';
  select id into l3 from public.airlines where world_id = w and iata_code = 'L3';
  select id into l4 from public.airlines where world_id = w and iata_code = 'L4';
  select id into l5 from public.airlines where world_id = w and iata_code = 'L5';
  select id into l6 from public.airlines where world_id = w and iata_code = 'L6';
  select id into l7 from public.airlines where world_id = w and iata_code = 'L7';
  insert into public.airlines (world_id, group_id, game_id, game_name, active) values (w, gr, 990399, 'Rival Air', true) returning id into rv;
  insert into public.airlines (world_id, group_id, game_id, game_name, active) values (w, gr, 990398, 'Quest Air', true) returning id into rq;
  insert into public.settings (world_id, airline_id, key, value, unit, description) values
    (w, l2, 'fare_launch_pct', '85'::jsonb, '% of standard', 'test: launches at 85%, as Ryanair'),
    (w, l3, 'fare_launch_pct', '55'::jsonb, '% of standard', 'test: launches at 55%, under the house floor'),
    (w, l6, 'fare_launch_pct', '85'::jsonb, '% of standard', 'test: launches at 85%, as Ryanair');
  insert into public.airline_bases (world_id, airline_id, airport_code, role, is_main, position) values
    (w, l1, 'ZA1', 'hub', true, 1), (w, l1, 'ZA2', 'hub', false, 2), (w, l2, 'ZR1', 'hub', true, 1),
    (w, l3, 'ZT1', 'hub', true, 1), (w, l4, 'ZD1', 'hub', true, 1), (w, l5, 'ZK1', 'hub', true, 1), (w, l6, 'ZW0', 'hub', true, 1),
    (w, l7, 'ZQ0', 'hub', true, 1);
  insert into public.aircraft_types (world_id, name, min_turn_min, cruise_kmh) values (w, 'LADDER TEST TYPE', 60, 800) returning id into ty;
  insert into public.cabin_configs (world_id, code, aircraft_type_id, cabin, seats, business_seats, economy_seats) values
    (w, 'LAD-Y', ty, 'Standard', 180, 0, 180) returning id into cy;
  insert into public.cabin_configs (world_id, code, aircraft_type_id, cabin, seats, business_seats, economy_seats) values
    (w, 'LAD-J', ty, 'Leisure', 180, 12, 168) returning id into cj;

  -- L1: two bases
  for x in select * from (values ('ZA1', 'ZB1', 1, 14), ('ZA1', 'ZB2', 2, 14), ('ZA1', 'ZB3', 3, 14), ('ZA1', 'ZB4', 4, 14), ('ZA1', 'ZB5', 5, 13),
                                 ('ZA1', 'ZB6', 6, 10), ('ZA1', 'ZA2', 7, 14), ('ZA2', 'ZC1', 8, 14), ('ZA2', 'ZC2', 9, 13), ('ZA2', 'ZC3', 10, 13),
                                 ('ZA2', 'ZC4', 11, 13)) v(hub, dest, k, sold) loop
    r := pg_temp.ladder_route(w, l1, x.hub, x.dest, x.k, 14, x.sold, date '2029-12-01', ty, cy);
    if x.dest = 'ZB6' then perform pg_temp.ladder_row(w, l1, r, 'economy', 110, 'up', date '2030-01-12'); end if;
  end loop;

  -- L2: Ryanair's 85% launch and its 105% cap
  -- (each route's first fares at 85% of a default price of 300, 255; ZS4's of 100, 85)
  r := pg_temp.ladder_route(w, l2, 'ZR1', 'ZS1', 21, 14, 14, date '2029-12-01', ty, cy, 255, base => 255);
  r := pg_temp.ladder_route(w, l2, 'ZR1', 'ZS2', 22, 14, 14, date '2029-12-01', ty, cy, 315, base => 255);
  perform pg_temp.ladder_row(w, l2, r, 'economy', 105, 'up', date '2030-01-12');
  r := pg_temp.ladder_route(w, l2, 'ZR1', 'ZS3', 23, 14, 14, date '2029-12-01', ty, cy, 306, base => 255);
  perform pg_temp.ladder_row(w, l2, r, 'economy', 102, 'up', date '2030-01-12');
  r := pg_temp.ladder_route(w, l2, 'ZR1', 'ZS4', 24, 14, 14, date '2029-12-01', ty, cy, 90, base => 85);
  perform pg_temp.ladder_row(w, l2, r, 'economy', 90, 'up', date '2030-01-12', 85, 5.9);
  update public.game_flights set eco_fare = case game_date when '2030-01-12' then 85 when '2030-01-13' then 88 else 90 end
   where airline_id = l2 and registration = 'ZL-24' and game_date >= '2030-01-12';
  insert into t_fl values ('zs4', to_jsonb(r));

  -- L3: the 60% floor where another player flies the pair
  -- (the fares at their levels of a default price of 300: launch 165)
  for x in select * from (values ('ZU1', 31, 62.0), ('ZU2', 32, 60.0), ('ZU3', 33, 60.0), ('ZU4', 34, null), ('ZU5', 35, 62.0)) v(dest, k, lvl) loop
    r := pg_temp.ladder_route(w, l3, 'ZT1', x.dest, x.k, 14, 10, date '2029-12-01', ty, cy, coalesce(x.lvl, 55) * 3, base => 165);
    if x.lvl is not null then perform pg_temp.ladder_row(w, l3, r, 'economy', x.lvl, 'down', date '2029-12-29'); end if;
  end loop;
  insert into public.game_scans (world_id, taken_at, status) values (w, '2030-01-17 08:00:00+00', 'done') returning id into sc;
  insert into public.game_scan_schedules (scan_id, world_id, airline_id, flights) values
    (sc, w, rv, '[["RV", 11, "ZU1", "ZT1", "1234567", "08:00", "09:00", "A320", ""], ["RV", 13, "ZT1", "ZU2", "135", "10:00", "11:00", "A320", ""]]'),
    -- L7's rival on 17 Jan, as on 16 Jan (below)
    (sc, w, rq, '[["QQ", 1, "ZQ0", "ZQ1", "1234567", "08:00", "09:00", "A320", ""], ["QQ", 2, "ZQ2", "ZQ0", "1234567", "08:00", "09:00", "A320", ""],
                  ["QQ", 3, "ZQ0", "ZQ2", "1234567", "12:00", "13:00", "A320", ""], ["QQ", 4, "ZQ0", "ZQ3", "1234567", "08:00", "09:00", "A320", ""],
                  ["QQ", 5, "ZQ3", "ZQ0", "135", "10:00", "11:00", "A320", ""], ["QQ", 6, "ZQ0", "ZQ4", "1234567", "08:00", "09:00", "A320", ""],
                  ["QQ", 7, "ZQ5", "ZQ0", "1234567", "08:00", "09:00", "A320", ""]]');
  -- the finished scans before it (the rival pause, L7): L3's rival on ZU1 and ZU2 in each, so it never started there;
  -- Quest Air on L7's pairs: on 4 Jan ZQ2 and ZQ3 daily; on 11 Jan ZQ4 starts; on 16 Jan ZQ1 and ZQ5 start, ZQ2 doubles
  -- (7 → 14) and ZQ3 gains 3 (7 → 10)
  for x in select * from (values (timestamptz '2030-01-04 08:00:00+00', '[["QQ", 2, "ZQ2", "ZQ0", "1234567", "08:00", "09:00", "A320", ""], ["QQ", 4, "ZQ0", "ZQ3", "1234567", "08:00", "09:00", "A320", ""]]'::jsonb),
                                 (timestamptz '2030-01-11 08:00:00+00', '[["QQ", 2, "ZQ2", "ZQ0", "1234567", "08:00", "09:00", "A320", ""], ["QQ", 4, "ZQ0", "ZQ3", "1234567", "08:00", "09:00", "A320", ""],
                                                                          ["QQ", 6, "ZQ0", "ZQ4", "1234567", "08:00", "09:00", "A320", ""]]'::jsonb),
                                 (timestamptz '2030-01-16 08:00:00+00', (select f.flights from public.game_scan_schedules f where f.scan_id = sc and f.airline_id = rq))) v(at, fl) loop
    insert into public.game_scans (world_id, taken_at, status) values (w, x.at, 'done') returning id into r;
    insert into public.game_scan_schedules (scan_id, world_id, airline_id, flights)
    select r, w, rv, f.flights from public.game_scan_schedules f where f.scan_id = sc and f.airline_id = rv
    union all select r, w, rq, x.fl;
  end loop;
  -- a later scan still running doesn't count
  insert into public.game_scans (world_id, taken_at, status) values (w, '2030-01-18 08:00:00+00', 'running') returning id into sc;
  insert into public.game_scan_schedules (scan_id, world_id, airline_id, flights) values
    (sc, w, rv, '[["RV", 15, "ZT1", "ZU3", "1234567", "08:00", "09:00", "A320", ""]]');

  -- L4: business seats
  r := pg_temp.ladder_route(w, l4, 'ZD1', 'ZE1', 41, 14, 14, date '2029-12-01', ty, cj, 360, 14);
  perform pg_temp.ladder_row(w, l4, r, 'economy', 120, 'up', date '2030-01-12');
  r := pg_temp.ladder_route(w, l4, 'ZD1', 'ZE2', 42, 14, 14, date '2029-12-01', ty, cj, 315, 13);
  perform pg_temp.ladder_row(w, l4, r, 'economy', 110, 'up', date '2030-01-05');
  perform pg_temp.ladder_row(w, l4, r, 'economy', 105, 'down', date '2030-01-12');
  r := pg_temp.ladder_route(w, l4, 'ZD1', 'ZE3', 43, 14, 14, date '2029-12-01', ty, cj, 315, 13);
  perform pg_temp.ladder_row(w, l4, r, 'economy', 105, 'down', date '2030-01-05');
  r := pg_temp.ladder_route(w, l4, 'ZD1', 'ZE4', 44, 8, 8, date '2030-01-15', ty, cj, 300, 8);
  r := pg_temp.ladder_route(w, l4, 'ZD1', 'ZE5', 45, 4, 4, date '2029-12-01', ty, cj, 300, 4);
  r := pg_temp.ladder_route(w, l4, 'ZD1', 'ZE6', 46, 14, 14, date '2029-12-01', ty, cj, 300, 13);
  perform pg_temp.ladder_row(w, l4, r, 'economy', 105, 'up', date '2030-01-19', 300, 5);
  r := pg_temp.ladder_route(w, l4, 'ZD1', 'ZE7', 47, 14, 13, date '2029-12-01', ty, cj, 315, 13);
  perform pg_temp.ladder_row(w, l4, r, 'economy', 105, 'up', date '2030-01-12');
  insert into public.game_flights (world_id, airline_id, game_date, flight_no, origin_code, dest_code, dep_local, dep_at, registration, eco_pct, eco_fare, loads_captured_at)
  values (w, l4, '2030-01-02', 5094, 'ZD1', 'ZE7', '14:00', '2030-01-02 14:00:00+00', 'ZL-47', 100, 300, '2030-01-03 11:00:00+00');
  r := pg_temp.ladder_route(w, l4, 'ZD1', 'ZE8', 48, 14, 13, date '2029-12-01', ty, cj, 300, 13);
  perform pg_temp.ladder_row(w, l4, r, 'business', 105, 'up', date '2030-01-12', 900, 5);
  update public.game_flights set bus_fare = case game_date when '2030-01-12' then 900 when '2030-01-13' then 930 when '2030-01-14' then 930 else 945 end
   where airline_id = l4 and registration = 'ZL-48' and game_date >= '2030-01-12';
  insert into t_fl values ('ze8', to_jsonb(r));
  -- both cabins sold out: to the same level (ZE9), and to different levels (ZEA, its economy a step up already)
  r := pg_temp.ladder_route(w, l4, 'ZD1', 'ZE9', 50, 14, 14, date '2029-12-01', ty, cj, 300, 14);
  r := pg_temp.ladder_route(w, l4, 'ZD1', 'ZEA', 51, 14, 14, date '2029-12-01', ty, cj, 315, 14);
  perform pg_temp.ladder_row(w, l4, r, 'economy', 105, 'up', date '2030-01-12');
  -- L4 flies ZU5–ZT1 too (no flights captured): the pair L3 flies is another of our airlines'
  r := pg_temp.ladder_route(w, l4, 'ZU5', 'ZT1', 49, 0, 0, date '2029-12-01', ty, cj);

  -- L5: new frequencies (part 1) and set-back changes (part 3)
  r := pg_temp.ladder_route(w, l5, 'ZK1', 'ZK2', 61, 14, 14, date '2029-12-01', ty, cy);
  insert into public.rotations (world_id, airline_id, route_id, launched_on) values (w, l5, r, date '2030-01-16') returning id into rot;
  insert into t_fl values ('zk2_rot', to_jsonb(rot));
  r := pg_temp.ladder_route(w, l5, 'ZK1', 'ZK3', 62, 14, 14, date '2030-01-16', ty, cy);
  r := pg_temp.ladder_route(w, l5, 'ZK1', 'ZK4', 63, 14, 14, date '2029-12-01', ty, cy);
  perform pg_temp.ladder_row(w, l5, r, 'economy', 110, 'up', date '2030-01-12');
  perform pg_temp.ladder_row(w, l5, r, 'economy', 115, 'up', date '2030-01-19', 300, 4.5);
  -- ZK5: on its latest day (18 Jan) two more flights out at 300, and its own flight out at 294 (98%)
  r := pg_temp.ladder_route(w, l5, 'ZK1', 'ZK5', 64, 14, 14, date '2029-12-01', ty, cy);
  insert into public.game_flights (world_id, airline_id, game_date, flight_no, origin_code, dest_code, dep_local, dep_at, registration,
                                   eco_pax, eco_seats, eco_pct, eco_fare, loads_captured_at)
  values (w, l5, '2030-01-18', 5900, 'ZK1', 'ZK5', '08:00', '2030-01-18 08:00:00+00', 'ZL-64', 180, 180, 100, 300, '2030-01-19 11:00:00+00'),
         (w, l5, '2030-01-18', 5901, 'ZK1', 'ZK5', '20:00', '2030-01-18 20:00:00+00', 'ZL-64', 180, 180, 100, 300, '2030-01-19 11:00:00+00');
  update public.game_flights set eco_fare = 294 where airline_id = l5 and game_date = '2030-01-18' and flight_no = 5128;
  -- ZK6: new, its flight out on its latest day (15 Jan) at 330 (110%)
  r := pg_temp.ladder_route(w, l5, 'ZK1', 'ZK6', 65, 8, 8, date '2030-01-15', ty, cy);
  update public.game_flights set eco_fare = 330 where airline_id = l5 and game_date = '2030-01-15' and flight_no = 5130;
  r := pg_temp.ladder_route(w, l5, 'ZK1', 'ZK7', 66, 14, 14, date '2029-12-01', ty, cj, 300, 14);
  perform pg_temp.ladder_row(w, l5, r, 'economy', 110, 'up', date '2030-01-12');
  perform pg_temp.ladder_row(w, l5, r, 'business', 110, 'up', date '2030-01-12');
  r := pg_temp.ladder_route(w, l5, 'ZK1', 'ZK8', 67, 14, 14, date '2029-12-01', ty, cy);
  perform pg_temp.ladder_row(w, l5, r, 'economy', 110, 'up', date '2030-01-12');
  insert into public.rotations (world_id, airline_id, route_id, launched_on) values (w, l5, r, date '2030-01-18');
  -- ZKA: launched 1 Nov; its first days only in the daily history (economy), its business first captured in the week
  r := pg_temp.ladder_route(w, l5, 'ZK1', 'ZKA', 68, 14, 13, date '2029-11-01', ty, cj, 300, 13, 990, with_base => false);
  perform pg_temp.ladder_history(w, l5, r, 'ZK1', 'ZKA', date '2029-11-02', 300);

  -- L6: Ryanair's early cuts, and the daily history on 21 Oct 2026
  r := pg_temp.ladder_route(w, l6, 'ZW0', 'ZW1', 71, 14, 14, date '2026-09-30', ty, cy, 255, with_base => false);
  perform pg_temp.ladder_day(w, l6, 'ZW0', 'ZW1', 71, date '2026-10-01', 300);
  perform pg_temp.ladder_day(w, l6, 'ZW0', 'ZW1', 71, date '2026-10-05', 255);
  perform pg_temp.ladder_day(w, l6, 'ZW0', 'ZW1', 71, date '2026-10-20', 255);
  perform pg_temp.ladder_day(w, l6, 'ZW0', 'ZW1', 71, date '2026-10-23', 255);
  r := pg_temp.ladder_route(w, l6, 'ZW0', 'ZW2', 72, 14, 14, date '2026-09-30', ty, cy, 255, with_base => false);
  perform pg_temp.ladder_history(w, l6, r, 'ZW0', 'ZW2', date '2026-10-21', 255);

  -- L7: the rival pause; ZQ5's second rotation launched 16 Jan (a flight added)
  for x in select * from (values ('ZQ1', 81), ('ZQ2', 82), ('ZQ3', 83), ('ZQ4', 84), ('ZQ5', 85)) v(dest, k) loop
    r := pg_temp.ladder_route(w, l7, 'ZQ0', x.dest, x.k, 14, 14, date '2029-12-01', ty, cy);
    if x.dest = 'ZQ5' then insert into public.rotations (world_id, airline_id, route_id, launched_on) values (w, l7, r, date '2030-01-16'); end if;
  end loop;

  perform set_config('equinox.actor', '', true), set_config('equinox.actor_detail', '', true);
  insert into t_fl values ('w', to_jsonb(w)), ('l1', to_jsonb(l1)), ('l2', to_jsonb(l2)), ('l3', to_jsonb(l3)), ('l4', to_jsonb(l4)),
                          ('l5', to_jsonb(l5)), ('l6', to_jsonb(l6)), ('l7', to_jsonb(l7)), ('t', to_jsonb(timestamptz '2030-01-19 12:00:00+00'));
end
$setup$;

-- each route and cabin of a ladder in one line: "hub-dest cabin move level>new (reason)"
create function pg_temp.ladder_line(d jsonb, dest text, cabin text default 'economy') returns text language sql as $f$
  select x ->> 'move' || ' ' || (x ->> 'level') || '>' || (x ->> 'new_level') || ' (' || (x ->> 'reason') || ')'
    from jsonb_array_elements(d -> 'routes') x where x ->> 'dest' = dest and x ->> 'cabin' = cabin
$f$;

-- ---------------------------------------------------------------- 3. L5: a new frequency holds the route for a week (spec part 1)
do $test$
declare l5 bigint := (select (v #>> '{}')::bigint from t_fl where k = 'l5'); t timestamptz := (select (v #>> '{}')::timestamptz from t_fl where k = 't');
  rot bigint := (select (v #>> '{}')::bigint from t_fl where k = 'zk2_rot'); d jsonb; e jsonb;
begin
  d := private.fig_fare_ladder(l5, t);
  assert d #>> '{settings,capacity_hold_days}' = '7', 'the hold isn''t fare_ladder_capacity_hold_days (7): ' || (d -> 'settings')::text;
  -- sold out 14 of 14, a rotation launched 3 days ago on a route flown since 1 Dec: holds, with the reason
  assert pg_temp.ladder_line(d, 'ZK2') = 'hold 100>100 (a flight added on 16 Jan: judged at its new size from 23 Jan)', 'ZK2: ' || pg_temp.ladder_line(d, 'ZK2');
  select x into e from jsonb_array_elements(d -> 'routes') x where x ->> 'dest' = 'ZK2';
  assert e ->> 'departures' = '14' and e ->> 'sold_out' = '14' and not (e ->> 'to_plan')::boolean and not (e ->> 'new_route')::boolean,
    'ZK2 isn''t sold out 14 of 14 with nothing to put on the fare plan: ' || e::text;
  -- a route whose only rotation is new is still a new route; a flight added on the latest captured day holds too
  assert pg_temp.ladder_line(d, 'ZK3') = 'hold 100>100 (new route, launched 16 Jan)', 'ZK3: ' || pg_temp.ladder_line(d, 'ZK3');
  assert pg_temp.ladder_line(d, 'ZK8') = 'hold 110>110 (a flight added on 18 Jan: judged at its new size from 25 Jan)', 'ZK8: ' || pg_temp.ladder_line(d, 'ZK8');
  -- planned first: ZK4, on the fare plan this week, isn't held by anything
  assert pg_temp.ladder_line(d, 'ZK4') = 'up 110>115 (test)', 'ZK4, on the fare plan: ' || pg_temp.ladder_line(d, 'ZK4');
  -- the same route 8 days after its new rotation launched: it moves
  update public.rotations set launched_on = date '2030-01-11' where id = rot;
  d := private.fig_fare_ladder(l5, t);
  assert pg_temp.ladder_line(d, 'ZK2') = 'up 100>105 (sold out 14 of 14)', 'ZK2, its new rotation 8 days old: ' || pg_temp.ladder_line(d, 'ZK2');
  update public.rotations set launched_on = date '2030-01-16' where id = rot;
  raise notice 'a new frequency (spec part 1): a route sold out 14 of 14 with a rotation launched 3 days ago holds ("a flight added on 16 Jan: judged at its new size from 23 Jan"); 8 days on it moves up; a route whose only rotation is new is still a new route; a move on the fare plan comes first';
end
$test$;

-- ---------------------------------------------------------------- 4. L5 and L6: the set-back changes and the fare index (spec part 3)
do $test$
declare l5 bigint := (select (v #>> '{}')::bigint from t_fl where k = 'l5'); l6 bigint := (select (v #>> '{}')::bigint from t_fl where k = 'l6');
  t timestamptz := (select (v #>> '{}')::timestamptz from t_fl where k = 't'); d jsonb; e jsonb; got text;
begin
  d := private.fig_fare_ladder(l5, t);
  -- each route and cabin: its index, whether it matches, and whether it is set back
  select string_agg(x ->> 'dest' || ' ' || (x ->> 'cabin') || ' ' || coalesce(x ->> 'fare_index', '—') || ' ' || coalesce(x ->> 'index_matches', '—')
                    || ' ' || (x ->> 'fix'), '; ' order by x ->> 'dest', x ->> 'cabin') into got
    from jsonb_array_elements(d -> 'routes') x;
  assert got = 'ZK2 economy 100.0 true false; ZK3 economy 100.0 true false; ZK4 economy 100.0 false false; ZK5 economy 99.5 false true; '
            || 'ZK6 economy 105.0 false false; ZK7 business 100.0 false true; ZK7 economy 100.0 false true; ZK8 economy 100.0 false false; '
            || 'ZKA business — — false; ZKA economy 100.0 true false',
    'L5''s fare indexes and set-backs are ' || got;
  -- each flight compared, not the day's average: ZK5's 99.5 is within a point, its flight at 294 (98%) isn't
  select x into e from jsonb_array_elements(d -> 'routes') x where x ->> 'dest' = 'ZK5';
  assert e ->> 'fix_reason' = 'captured fare at 98%, level 100%' and e ->> 'move' = 'up' and e ->> 'latest_on' = '2030-01-18',
    'ZK5 isn''t set back for its flight at 98% (its move still up): ' || e::text;
  -- the economy's baseline from the daily history; no business index once its first days are archived
  select x into e from jsonb_array_elements(d -> 'routes') x where x ->> 'dest' = 'ZKA' and x ->> 'cabin' = 'economy';
  assert e ->> 'baseline_on' = '2029-11-02' and (e ->> 'baseline_fare')::numeric = 300, 'ZKA''s economy baseline isn''t the daily history''s 300 on 2 Nov: ' || e::text;
  select x into e from jsonb_array_elements(d -> 'routes') x where x ->> 'dest' = 'ZKA' and x ->> 'cabin' = 'business';
  assert e ->> 'baseline_fare' is null and (e ->> 'latest_fare')::numeric = 990, 'ZKA''s business has a baseline, though its first days are gone: ' || e::text;
  -- the set-back changes first: ZK5 at +0% (100), ZK7's both cabins at +10% in one action each way; then the week's moves
  select string_agg(x ->> 'n' || '. ' || (x ->> 'text') || ' [' || (x ->> 'reason') || ']', ' | ' order by (x ->> 'n')::int) into got
    from jsonb_array_elements(d -> 'actions') x where (x ->> 'fix')::boolean;
  assert got = '1. From ZK1 to ZK5: +0% of the default price, economy [captured fare at 98%, level 100%] | '
            || '2. From ZK5 to ZK1: +0% of the default price, economy [captured fare at 98%, level 100%] | '
            || '3. From ZK1 to ZK7: +10% of the default price, economy and business [economy: captured fare at 100%, level 110%; business: captured fare at 100%, level 110%] | '
            || '4. From ZK7 to ZK1: +10% of the default price, economy and business [economy: captured fare at 100%, level 110%; business: captured fare at 100%, level 110%]',
    'L5''s set-back changes are ' || coalesce(got, 'none');
  assert (select min((x ->> 'n')::int) from jsonb_array_elements(d -> 'actions') x where not (x ->> 'fix')::boolean) = 5
     and (d ->> 'off_level')::int = 2 and jsonb_array_length(d -> 'actions') > 4,
    'the week''s moves don''t follow the 4 set-back changes, or off_level isn''t 2: ' || (d ->> 'off_level');
  -- none for a route on the fare plan this week (ZK4), a new route (ZK6), or one not captured since its newest rotation (ZK8)
  assert not exists (select 1 from jsonb_array_elements(d -> 'actions') x where (x ->> 'fix')::boolean and x ->> 'route' in ('ZK1–ZK4', 'ZK1–ZK6', 'ZK1–ZK8')),
    'a set-back change for a planned, new or not yet captured route: ' || (d -> 'actions')::text;

  -- L6 (launch 85%): the baseline of 21 Oct 2026, Ryanair's early cuts and the daily history
  d := private.fig_fare_ladder(l6, t);
  select string_agg(x ->> 'dest' || ' ' || (x ->> 'fare_index') || ' ' || (x ->> 'index_matches') || ' ' || (x ->> 'baseline_on') || ' ' || trim_scale((x ->> 'baseline_fare')::numeric),
                    '; ' order by x ->> 'dest') into got
    from jsonb_array_elements(d -> 'routes') x;
  assert got = 'ZW1 85.0 true 2026-10-20 255; ZW2 85.0 true 2026-10-21 255' and (d ->> 'off_level')::int = 0 and d #>> '{settings,baseline_day}' = '2026-10-21',
    'L6''s routes aren''t at 85 from their fares of 20 and 21 Oct 2026: ' || coalesce(got, 'none');
  raise notice 'set back (spec part 3): a route at 100%% against 110%% gets two fix actions at +10%% (both classes in one action each way when both cabins are off), first in the list with the reason; none for one on the fare plan this week, a new route, or one not captured since its newest rotation launched; each flight compared (one at 98%% among four, the day''s average 99.5); a cut early in October read from its fare of 20 Oct 2026 (85, not 72), the daily history''s fare of 21 Oct, no business index once its first days are archived';
end
$test$;

-- ---------------------------------------------------------------- 5. L1: two bases, the moves and the game actions
do $test$
declare l1 bigint := (select (v #>> '{}')::bigint from t_fl where k = 'l1'); t timestamptz := (select (v #>> '{}')::timestamptz from t_fl where k = 't');
  d jsonb; got text; want text;
begin
  d := private.fig_fare_ladder(l1, t);
  assert d ->> 'week_of' = '2030-01-19', 'this Saturday isn''t 19 Jan: ' || (d ->> 'week_of');
  assert (select count(*) from jsonb_array_elements(d -> 'routes')) = 11 and not exists (select 1 from jsonb_array_elements(d -> 'routes') x where x ->> 'cabin' <> 'economy'),
    'L1 hasn''t its 11 routes in economy only: ' || (d -> 'routes')::text;
  select string_agg(x ->> 'dest' || ' ' || pg_temp.ladder_line(d, x ->> 'dest'), '; ' order by x ->> 'hub', x ->> 'dest') into got from jsonb_array_elements(d -> 'routes') x;
  want := 'ZA2 up 100>105 (sold out 14 of 14); ZB1 up 100>105 (sold out 14 of 14); ZB2 up 100>105 (sold out 14 of 14); ZB3 up 100>105 (sold out 14 of 14); '
       || 'ZB4 up 100>105 (sold out 14 of 14); ZB5 hold 100>100 (sold out 13 of 14); ZB6 down 110>105 (sold out 10 of 14); ZC1 up 100>105 (sold out 14 of 14); '
       || 'ZC2 hold 100>100 (sold out 13 of 14); ZC3 hold 100>100 (sold out 13 of 14); ZC4 hold 100>100 (sold out 13 of 14)';
  assert got = want, 'L1''s moves are ' || got;
  assert d -> 'moves' = '{"up": 6, "hold": 4, "down": 1}'::jsonb, 'L1''s moves aren''t 6 up, 4 hold, 1 down: ' || (d -> 'moves')::text;
  assert (d ->> 'to_plan')::int = 7 and (d ->> 'planned')::int = 0, 'Put on the fare plan doesn''t write the 7 changed levels: ' || (d ->> 'to_plan');
  -- the steps, the departures and the share
  assert (select x ->> 'departures' = '14' and x ->> 'sold_out' = '10' and (x ->> 'sold_out_share')::numeric = 71.4 and x ->> 'steps' = '2' and x ->> 'new_steps' = '1'
                 and (x ->> 'change_pct')::numeric = -4.5 and (x ->> 'recorded')::boolean
            from jsonb_array_elements(d -> 'routes') x where x ->> 'dest' = 'ZB6'),
    'ZB6 isn''t 10 of 14 (71.4%), 2 steps above launch going to 1 (−4.5%), from the fare plan: ' || (select x::text from jsonb_array_elements(d -> 'routes') x where x ->> 'dest' = 'ZB6');
  -- the fare index: every captured fare 300 against a first fare of 300, so 100 everywhere; ZB6 recorded at 110 doesn't
  -- match it, so it is set back to 110 (spec docs/specs/2026-10-21-frequencies-and-fares.md §3), its move as it was
  assert (select string_agg(x ->> 'dest', ',' order by x ->> 'dest') from jsonb_array_elements(d -> 'routes') x where not (x ->> 'index_matches')::boolean) = 'ZB6'
     and (select (x ->> 'fare_index')::numeric from jsonb_array_elements(d -> 'routes') x where x ->> 'dest' = 'ZB6') = 100,
    'only ZB6 (index 100 against 110) should be flagged: ' || (d -> 'routes')::text;
  assert (select string_agg(x ->> 'dest' || ' ' || (x ->> 'fix_reason') || ' ' || (x ->> 'move'), ',') from jsonb_array_elements(d -> 'routes') x where (x ->> 'fix')::boolean)
       = 'ZB6 captured fare at 100%, level 110% down' and (d ->> 'off_level')::int = 1,
    'only ZB6 should be set back ("captured fare at 100%, level 110%"), its move still down: ' || (d -> 'routes')::text;
  assert (select (x ->> 'baseline_fare')::numeric = 300 and x ->> 'baseline_on' = '2029-12-02' and (x ->> 'latest_fare')::numeric = 300 and x ->> 'latest_on' = '2030-01-18'
            from jsonb_array_elements(d -> 'routes') x where x ->> 'dest' = 'ZB6'),
    'ZB6''s baseline isn''t 300 on 2 Dec (its first captured day), its latest 300 on 18 Jan: ' || (select x::text from jsonb_array_elements(d -> 'routes') x where x ->> 'dest' = 'ZB6');
  -- route by route only (21 Oct): ZB6 set back first, then each route that moves, both ways, in the routes' order; no base
  -- action, none for a hold
  select string_agg(x ->> 'n' || '. ' || (x ->> 'text'), ' | ' order by (x ->> 'n')::int) into got from jsonb_array_elements(d -> 'actions') x;
  want := '1. From ZA1 to ZB6: +10% of the default price, economy | 2. From ZB6 to ZA1: +10% of the default price, economy | '
       || '3. From ZA1 to ZA2: +5% of the default price, economy | 4. From ZA2 to ZA1: +5% of the default price, economy | '
       || '5. From ZA1 to ZB1: +5% of the default price, economy | 6. From ZB1 to ZA1: +5% of the default price, economy | '
       || '7. From ZA1 to ZB2: +5% of the default price, economy | 8. From ZB2 to ZA1: +5% of the default price, economy | '
       || '9. From ZA1 to ZB3: +5% of the default price, economy | 10. From ZB3 to ZA1: +5% of the default price, economy | '
       || '11. From ZA1 to ZB4: +5% of the default price, economy | 12. From ZB4 to ZA1: +5% of the default price, economy | '
       || '13. From ZA1 to ZB6: +5% of the default price, economy | 14. From ZB6 to ZA1: +5% of the default price, economy | '
       || '15. From ZA2 to ZC1: +5% of the default price, economy | 16. From ZC1 to ZA2: +5% of the default price, economy';
  assert got = want, 'L1''s game actions are ' || got;
  -- the two set-back changes: fix, at +10% (110), with the reason; the moves aren't fixes and carry no reason
  assert (select count(*) from jsonb_array_elements(d -> 'actions') x
           where (x ->> 'fix')::boolean and x ->> 'route' = 'ZA1–ZB6' and x -> 'sign' = '"+"'::jsonb and x -> 'pct' = '10'::jsonb and x -> 'level' = '110'::jsonb
             and x -> 'classes' = '["economy"]'::jsonb and x ->> 'reason' = 'captured fare at 100%, level 110%' and (x ->> 'n')::int <= 2) = 2
     and not exists (select 1 from jsonb_array_elements(d -> 'actions') x where (x ->> 'n')::int > 2 and ((x ->> 'fix')::boolean or x ->> 'reason' is not null)),
    'ZB6''s set-back changes aren''t the first two, fix at +10% with the reason, or a move is marked fix: ' || (d -> 'actions')::text;
  assert (select x -> 'sign' = '"+"'::jsonb and x -> 'pct' = '5'::jsonb and x -> 'level' = '105'::jsonb and x ->> 'baseline' = 'default price'
                 and x -> 'classes' = '["economy"]'::jsonb and x ->> 'route' = 'ZA1–ZA2' and x ->> 'from' = 'ZA1' and x ->> 'to' = 'ZA2'
            from jsonb_array_elements(d -> 'actions') x where (x ->> 'n')::int = 3),
    'the first move''s fields aren''t +, 5, 105, default price, ["economy"], ZA1–ZA2 from ZA1 to ZA2: ' || (d -> 'actions' -> 2)::text;
  assert not exists (select 1 from jsonb_array_elements(d -> 'actions') x where x ? 'kind' or x ? 'base' or x ? 'cabin' or x ->> 'from' = 'anywhere' or x ->> 'to' = 'anywhere'),
    'an action still has a base, a kind or a cabin: ' || (d -> 'actions')::text;
  insert into t_fl values ('l1_ladder', d);
  raise notice 'L1: 6 up, 4 hold, 1 down; 7 rows to put on the fare plan; ZB6''s index (100 against 110) flagged, and its 2 set-back changes at +10%% first; then 14 game actions, route by route: each of the 7 routes that move both ways (ZA1–ZA2, between the two bases, like any other), economy, none for the 4 that hold, no base action';
end
$test$;

-- ---------------------------------------------------------------- 6. L2: Ryanair's 85% and its cap
do $test$
declare l2 bigint := (select (v #>> '{}')::bigint from t_fl where k = 'l2'); t timestamptz := (select (v #>> '{}')::timestamptz from t_fl where k = 't');
  d jsonb; got text;
begin
  d := private.fig_fare_ladder(l2, t);
  assert d #>> '{settings,launch_pct}' = '85' and d #>> '{settings,cap_pct}' = '105', 'L2 doesn''t launch at 85% with its cap at 105%: ' || (d -> 'settings')::text;
  select string_agg(x ->> 'dest' || ' ' || pg_temp.ladder_line(d, x ->> 'dest'), '; ' order by x ->> 'dest') into got from jsonb_array_elements(d -> 'routes') x;
  assert got = 'ZS1 up 85>90 (sold out 14 of 14); ZS2 hold 105>105 (sold out 14 of 14, capped at 105%); ZS3 up 102>105 (sold out 14 of 14, up to the 105% cap); ZS4 up 90>95 (sold out 14 of 14)',
    'L2''s moves are ' || got;
  assert not exists (select 1 from jsonb_array_elements(d -> 'routes') x where x ->> 'cabin' = 'business'), 'L2 has business rows: it has no business seats';
  select string_agg(x ->> 'text', ' | ' order by (x ->> 'n')::int) into got from jsonb_array_elements(d -> 'actions') x;
  assert got = 'From ZR1 to ZS1: −10% of the default price, economy | From ZS1 to ZR1: −10% of the default price, economy | '
            || 'From ZR1 to ZS3: +5% of the default price, economy | From ZS3 to ZR1: +5% of the default price, economy | '
            || 'From ZR1 to ZS4: −5% of the default price, economy | From ZS4 to ZR1: −5% of the default price, economy',
    'L2''s game actions are ' || got;
  assert not exists (select 1 from jsonb_array_elements(d -> 'actions') x where x -> 'classes' <> '["economy"]'::jsonb or x ->> 'route' = 'ZR1–ZS2'),
    'L2''s actions aren''t economy only, or capped ZS2 has one: ' || (d -> 'actions')::text;
  -- each fare at its level against a first fare of 85% (255; ZS4 85 on a default price of 100): no set-back
  assert (select string_agg(x ->> 'dest' || ' ' || (x ->> 'fare_index'), ', ' order by x ->> 'dest') from jsonb_array_elements(d -> 'routes') x)
       = 'ZS1 85.0, ZS2 105.0, ZS3 102.0, ZS4 90.0' and (d ->> 'off_level')::int = 0,
    'L2''s fare indexes aren''t 85, 105, 102 and 90 with nothing set back: ' || (d -> 'routes')::text;
  raise notice 'L2: ZS1 85 up to 90, ZS2 capped at 105, ZS3 102 up to the 105 cap, ZS4 90 up to 95, each its fare index; economy only; 3 routes, 6 actions, none for capped ZS2';
end
$test$;

-- ---------------------------------------------------------------- 7. L3: the 60% floor and the launch floor
do $test$
declare l3 bigint := (select (v #>> '{}')::bigint from t_fl where k = 'l3'); t timestamptz := (select (v #>> '{}')::timestamptz from t_fl where k = 't');
  d jsonb; got text;
begin
  d := private.fig_fare_ladder(l3, t);
  select string_agg(x ->> 'dest' || ' ' || pg_temp.ladder_line(d, x ->> 'dest') || case when (x ->> 'contested')::boolean then ' contested' else '' end, '; ' order by x ->> 'dest')
    into got from jsonb_array_elements(d -> 'routes') x;
  assert got = 'ZU1 down 62>60 (sold out 10 of 14, down to the 60% floor) contested; ZU2 hold 60>60 (sold out 10 of 14, at the 60% floor) contested; '
            || 'ZU3 down 60>55 (sold out 10 of 14, down to launch (55%)); ZU4 hold 55>55 (sold out 10 of 14, at launch (55%)); '
            || 'ZU5 down 62>60 (sold out 10 of 14, down to the 60% floor) contested',
    'L3''s moves are ' || got;
  assert (d #>> '{scan,taken_at}') = '2030-01-17T08:00:00.000Z', 'the scan read isn''t the latest finished one by then: ' || (d -> 'scan')::text;
  assert (d ->> 'off_level')::int = 0, 'L3 has a route off its level, every fare at it: ' || (d -> 'routes')::text;
  raise notice 'L3 (launch 55%%): 60%% floor where a rival (the latest finished scan) or our own airline flies the pair, launch where none does';
end
$test$;

-- ---------------------------------------------------------------- 8. L4: cabins, the hold after a step down, new routes, few departures, this week's plan, the index
do $test$
declare l4 bigint := (select (v #>> '{}')::bigint from t_fl where k = 'l4'); t timestamptz := (select (v #>> '{}')::timestamptz from t_fl where k = 't');
  d jsonb; got text; e jsonb;
begin
  d := private.fig_fare_ladder(l4, t);
  assert pg_temp.ladder_line(d, 'ZE1') = 'hold 120>120 (sold out 14 of 14, capped at 120%)', 'ZE1 economy: ' || pg_temp.ladder_line(d, 'ZE1');
  assert pg_temp.ladder_line(d, 'ZE1', 'business') = 'up 100>105 (sold out 14 of 14)', 'ZE1 business, a cabin of its own: ' || pg_temp.ladder_line(d, 'ZE1', 'business');
  assert pg_temp.ladder_line(d, 'ZE2') = 'hold 105>105 (held after a step down on 12 Jan)', 'ZE2: ' || pg_temp.ladder_line(d, 'ZE2');
  assert pg_temp.ladder_line(d, 'ZE2', 'business') = 'hold 100>100 (sold out 13 of 14)', 'ZE2 business: ' || pg_temp.ladder_line(d, 'ZE2', 'business');
  assert pg_temp.ladder_line(d, 'ZE3') = 'up 105>110 (sold out 14 of 14)', 'ZE3, two weeks after its step down: ' || pg_temp.ladder_line(d, 'ZE3');
  assert pg_temp.ladder_line(d, 'ZE4') = 'hold 100>100 (new route, launched 15 Jan)', 'ZE4: ' || pg_temp.ladder_line(d, 'ZE4');
  assert pg_temp.ladder_line(d, 'ZE5') = 'hold 100>100 (4 departures captured, needs 5)', 'ZE5: ' || pg_temp.ladder_line(d, 'ZE5');
  assert pg_temp.ladder_line(d, 'ZE6') = 'up 100>105 (test)', 'ZE6, on the fare plan this Saturday: ' || pg_temp.ladder_line(d, 'ZE6');
  assert pg_temp.ladder_line(d, 'ZT1') = 'hold 100>100 (no departures captured)', 'ZU5–ZT1, no flights captured: ' || coalesce(pg_temp.ladder_line(d, 'ZT1'), 'none');
  select x into e from jsonb_array_elements(d -> 'routes') x where x ->> 'dest' = 'ZE6' and x ->> 'cabin' = 'economy';
  assert (e ->> 'planned')::boolean and not (e ->> 'to_plan')::boolean and e ->> 'plan_id' is not null, 'ZE6 isn''t planned already: ' || e::text;
  select x into e from jsonb_array_elements(d -> 'routes') x where x ->> 'dest' = 'ZE2' and x ->> 'cabin' = 'economy';
  assert (e ->> 'to_plan')::boolean, 'ZE2''s hold after a step down has nothing to record: ' || e::text;
  select string_agg(x ->> 'dest' || ' ' || (x ->> 'cabin'), ', ' order by x ->> 'dest', x ->> 'cabin') into got
    from jsonb_array_elements(d -> 'routes') x where (x ->> 'to_plan')::boolean;
  assert got = 'ZE1 business, ZE2 economy, ZE3 economy, ZE9 business, ZE9 economy, ZEA business, ZEA economy', 'Put on the fare plan would write ' || got;
  assert pg_temp.ladder_line(d, 'ZE9') = 'up 100>105 (sold out 14 of 14)' and pg_temp.ladder_line(d, 'ZE9', 'business') = 'up 100>105 (sold out 14 of 14)',
    'ZE9, both cabins to 105: ' || pg_temp.ladder_line(d, 'ZE9') || ' / ' || pg_temp.ladder_line(d, 'ZE9', 'business');
  assert pg_temp.ladder_line(d, 'ZEA') = 'up 105>110 (sold out 14 of 14)' and pg_temp.ladder_line(d, 'ZEA', 'business') = 'up 100>105 (sold out 14 of 14)',
    'ZEA, economy to 110 and business to 105: ' || pg_temp.ladder_line(d, 'ZEA') || ' / ' || pg_temp.ladder_line(d, 'ZEA', 'business');
  -- the game actions, route by route (21 Oct): one cabin moving gets its own two; both to the same level, one each way
  -- with both classes (ZE9); to different levels, one each way per cabin, economy first (ZEA). ZE1's capped economy, held
  -- ZE2, new ZE4, ZE5 with 4 departures and the holds get none
  select string_agg(x ->> 'n' || '. ' || (x ->> 'text'), ' | ' order by (x ->> 'n')::int) into got from jsonb_array_elements(d -> 'actions') x;
  assert got = '1. From ZD1 to ZE1: +5% of the default price, business | 2. From ZE1 to ZD1: +5% of the default price, business | '
            || '3. From ZD1 to ZE3: +10% of the default price, economy | 4. From ZE3 to ZD1: +10% of the default price, economy | '
            || '5. From ZD1 to ZE6: +5% of the default price, economy | 6. From ZE6 to ZD1: +5% of the default price, economy | '
            || '7. From ZD1 to ZE9: +5% of the default price, economy and business | 8. From ZE9 to ZD1: +5% of the default price, economy and business | '
            || '9. From ZD1 to ZEA: +10% of the default price, economy | 10. From ZEA to ZD1: +10% of the default price, economy | '
            || '11. From ZD1 to ZEA: +5% of the default price, business | 12. From ZEA to ZD1: +5% of the default price, business',
    'L4''s game actions are ' || got;
  select string_agg(x ->> 'n' || ' ' || (x -> 'classes')::text, ', ' order by (x ->> 'n')::int) into got from jsonb_array_elements(d -> 'actions') x;
  assert got = '1 ["business"], 2 ["business"], 3 ["economy"], 4 ["economy"], 5 ["economy"], 6 ["economy"], 7 ["economy", "business"], '
            || '8 ["economy", "business"], 9 ["economy"], 10 ["economy"], 11 ["business"], 12 ["business"]',
    'L4''s actions'' classes are ' || got;
  assert (select x ->> 'route' = 'ZD1–ZE9' and x ->> 'from' = 'ZE9' and x ->> 'to' = 'ZD1' and x -> 'level' = '105'::jsonb and x ->> 'sign' = '+' and x -> 'pct' = '5'::jsonb
            from jsonb_array_elements(d -> 'actions') x where (x ->> 'n')::int = 8),
    'action 8 isn''t ZD1–ZE9 from ZE9 to ZD1 at 105 (+5): ' || (d -> 'actions' -> 7)::text;
  -- the fare index: its first fare 300 (2 Dec, the day after it launched), 315 now, launch 100 → 105, as recorded
  select x into e from jsonb_array_elements(d -> 'routes') x where x ->> 'dest' = 'ZE7' and x ->> 'cabin' = 'economy';
  assert (e ->> 'fare_index')::numeric = 105 and (e ->> 'index_matches')::boolean and e ->> 'baseline_on' = '2029-12-02' and (e ->> 'baseline_fare')::numeric = 300
     and (e ->> 'latest_fare')::numeric = 315, 'ZE7''s fare index isn''t 105 (its first fare 300 on 2 Dec, 315 now), matching its level: ' || e::text;
  assert d -> 'moves' = '{"up": 7, "hold": 15, "down": 0}'::jsonb, 'L4''s moves: ' || (d -> 'moves')::text;
  assert (d ->> 'off_level')::int = 0 and not exists (select 1 from jsonb_array_elements(d -> 'routes') x where not (x ->> 'index_matches')::boolean),
    'L4 has a route off its level, every fare at it: ' || (d -> 'routes')::text;
  -- the rival pause is built (competition analysis, spec §2): the note that said it waited for step 4 is gone
  assert jsonb_array_length(d -> 'notes') = 1 and d ->> 'notes' not like '%step 4%' and d ->> 'notes' like '%fare index%',
    'the notes still say rivals'' pauses wait for step 4, or lost the fare index''s: ' || (d -> 'notes')::text;
  raise notice 'L4: economy capped at 120%% while business climbs; held 2 weeks after a step down (with a hold to record), then climbs; a new route and 4 departures hold; this Saturday''s move already on the fare plan; the fare index 105 from 300 to 315; 12 game actions: one cabin moving (2 each), both cabins to 105 (ZE9: 2, both classes), to 110 and 105 (ZEA: 4, one per cabin each way), none for the capped, held, new and few';
end
$test$;

-- ---------------------------------------------------------------- 9. fare_plan_status(): the ladder's rows
do $test$
declare l2 bigint := (select (v #>> '{}')::bigint from t_fl where k = 'l2'); l4 bigint := (select (v #>> '{}')::bigint from t_fl where k = 'l4');
  t timestamptz := (select (v #>> '{}')::timestamptz from t_fl where k = 't'); zs4 bigint := (select (v #>> '{}')::bigint from t_fl where k = 'zs4');
  ze8 bigint := (select (v #>> '{}')::bigint from t_fl where k = 'ze8'); p jsonb;
begin
  -- economy: 85 → 90 is +5.9%; 88 on 13 Jan is more than half of it but not within 1%, 90 on 14 Jan is
  select x into p from jsonb_array_elements(private.fig_fare_plan(l2, t) -> 'plan') x where (x ->> 'route_id')::bigint = zs4;
  assert (p ->> 'applied')::boolean and p ->> 'seen_on' = '2030-01-14' and p ->> 'level_pct' = '90' and p ->> 'ladder_move' = 'up' and (p ->> 'fare_now')::numeric = 90,
    'ZS4''s ladder row isn''t seen on 14 Jan (88 on 13 Jan under the ratio): ' || p::text;
  -- business: read in business, 900 → 945 (+5%) seen on 15 Jan; the economy fare never moved
  select x into p from jsonb_array_elements(private.fig_fare_plan(l4, t) -> 'plan') x where (x ->> 'route_id')::bigint = ze8;
  assert (p ->> 'applied')::boolean and p ->> 'seen_on' = '2030-01-15' and (p ->> 'fare_now')::numeric = 945 and (p ->> 'target')::numeric = 945
     and (p ->> 'economy_before')::numeric = 100 and (p ->> 'economy_after')::numeric < 100,
    'ZE8''s business ladder row isn''t read in business, seen on 15 Jan: ' || p::text;
  raise notice 'fare_plan_status(): a ladder row is seen when the fare moves by its ratio within 1%% (14 Jan, not 13 Jan''s 88 at half the change), a business one in business (15 Jan, 945)';
end
$test$;

-- ---------------------------------------------------------------- 10. who is refused; staff get what postgres gets
set local role anon;
do $test$
declare l1 bigint := (select (v #>> '{}')::bigint from t_fl where k = 'l1'); n int := 0;
begin
  begin perform public.fare_ladder(l1); exception when insufficient_privilege then n := n + 1; end;
  assert n = 1, 'signed out, fare_ladder() wasn''t refused';
end
$test$;
reset role;

do $$ begin perform set_config('request.jwt.claims',
  '{"sub": "00000000-0000-4000-8000-0000000000f1", "email": "fare-ladder-other@example.com", "role": "authenticated"}', true); end $$;
set local role authenticated;
do $test$
declare l1 bigint := (select (v #>> '{}')::bigint from t_fl where k = 'l1'); n int := 0;
begin
  begin perform public.fare_ladder(l1); exception when insufficient_privilege then n := n + 1; end;
  assert n = 1, 'an account that isn''t staff wasn''t refused fare_ladder()';
end
$test$;
reset role;

do $$ begin perform set_config('request.jwt.claims',
  '{"sub": "00000000-0000-4000-8000-0000000000f2", "email": "fare-ladder-staff@example.com", "role": "authenticated"}', true); end $$;
set local role authenticated;
do $test$
declare l1 bigint := (select (v #>> '{}')::bigint from t_fl where k = 'l1'); t timestamptz := (select (v #>> '{}')::timestamptz from t_fl where k = 't');
begin
  assert public.fare_ladder(l1, t) = (select v from t_fl where k = 'l1_ladder'), 'staff don''t get what postgres gets from fare_ladder()';
end
$test$;
reset role;
do $test$ begin raise notice 'signed out and an account that isn''t staff are refused fare_ladder(); staff get what postgres gets'; end $test$;

-- ---------------------------------------------------------------- 11. L7: the rival pause (competition analysis, spec §2)
do $test$
declare l7 bigint := (select (v #>> '{}')::bigint from t_fl where k = 'l7'); t timestamptz := (select (v #>> '{}')::timestamptz from t_fl where k = 't');
  d jsonb; got text;
begin
  d := private.fig_fare_ladder(l7, t);
  select string_agg(x ->> 'dest' || ' ' || pg_temp.ladder_line(d, x ->> 'dest'), '; ' order by x ->> 'dest') into got from jsonb_array_elements(d -> 'routes') x;
  assert got = 'ZQ1 hold 100>100 (rival Quest Air started here on 16 Jan: paused until 23 Jan); '
            || 'ZQ2 hold 100>100 (rival Quest Air added 7 a week here on 16 Jan: paused until 23 Jan); '
            || 'ZQ3 up 100>105 (sold out 14 of 14); ZQ4 up 100>105 (sold out 14 of 14); '
            || 'ZQ5 hold 100>100 (a flight added on 16 Jan: judged at its new size from 23 Jan)',
    'L7''s moves are ' || got;
  assert (select string_agg(x ->> 'route', ',' order by (x ->> 'n')::int) from jsonb_array_elements(d -> 'actions') x) = 'ZQ0–ZQ3,ZQ0–ZQ3,ZQ0–ZQ4,ZQ0–ZQ4',
    'a paused route has a game action, or a moving one hasn''t: ' || (d -> 'actions')::text;
  assert (select string_agg(x ->> 'dest', ',' order by x ->> 'dest') from jsonb_array_elements(d -> 'routes') x where (x ->> 'to_plan')::boolean) = 'ZQ3,ZQ4',
    'Put on the fare plan would write a paused route: ' || (d -> 'routes')::text;
  -- the same threats as competition() lists (one home, private.competition_threats())
  assert (select string_agg(x ->> 'route' || ' ' || (x ->> 'kind'), ', ' order by x ->> 'route') from jsonb_array_elements(private.fig_competition(l7, t) -> 'threats') x)
       = 'ZQ0–ZQ1 started, ZQ0–ZQ2 added, ZQ0–ZQ5 started',
    'competition() lists other threats than the fare ladder pauses: ' || (private.fig_competition(l7, t) -> 'threats')::text;
  -- a week on (26 Jan, the threats of 16 Jan gone): nothing paused
  d := private.fig_fare_ladder(l7, t + interval '7 days');
  assert not exists (select 1 from jsonb_array_elements(d -> 'routes') x where x ->> 'reason' like 'rival %'),
    'a threat older than 7 days still pauses a route: ' || (d -> 'routes')::text;
  raise notice 'the rival pause: a rival that started (ZQ1) or added 7 a week (ZQ2) in a scan of the last 7 days holds the route ("rival Quest Air started here on 16 Jan: paused until 23 Jan"), with no game action and nothing to put on the fare plan; 3 added (ZQ3) or a start 8 days before (ZQ4) doesn''t; a flight added comes first (ZQ5); the threats are competition()''s; a week on nothing is paused';
end
$test$;

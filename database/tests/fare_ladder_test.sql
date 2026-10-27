-- The fare ladder (manual §5; migrations 20261021120000_fare_ladder.sql, 20261021190000_fare_actions_by_route.sql,
-- 20261021230000_frequencies_and_fares.sql and 20261021235000_competition.sql; specs docs/specs/2026-10-21-fare-ladder.md,
-- docs/specs/2026-10-21-fare-actions-by-route.md, docs/specs/2026-10-21-frequencies-and-fares.md and
-- docs/specs/2026-10-21-competition-analysis.md §2; since 26 Oct per direction, migration
-- 20261026220000_fare_ladder_per_direction.sql, spec docs/specs/2026-10-26-fare-ladder-per-direction.md; the hold after a
-- step up since 26 Oct, migration 20261027000000_fare_ladder_up_hold.sql). Run by
-- database/rehearse.sh on the copy of last night's backup, after the new migrations, inside a transaction that is rolled
-- back. A failed check stops with an error that says which (codes, levels, moves and words of the hand-made routes only).
-- Everything is made in a world of its own, so nothing on the copy is touched or counted.
--   The moment T is Saturday 19 Jan 2030, 12:00 UTC: the week is the 7 days before it. Each route flies 14 departures in
--   it (out and back, daily), each one's economy load 100% (sold out) or 80%, its fare 300 unless said; every airport is
--   on UTC. Since 26 Oct each direction is judged on its own 7: the sold-out flights are the first ones, out and back in
--   turn, so a route sold out 13 of 14 is out 7 of 7 (up) and back 6 of 7 (under 90%: holds at launch, or steps down
--   above it), and 10 of 14 is 5 of 7 each way. The counts and actions below are per direction. A route launched before the week also has an out and back the day after it launched at its launch level's
--   fare (the fare index's baseline: its first captured fare, since it launched after 21 Oct 2026). Six of our airlines:
--     L1 (launch 100%; bases ZA1 then ZA2, economy only): ZA1 to ZB1, ZB2, ZB3, ZB4 sold out 14 of 14 (up to 105); ZB5 13
--        of 14 (hold); ZB6 at 110% since 12 Jan, 10 of 14 (down to 105; its fares at 100%, so it is set back to 110 first);
--        ZA1–ZA2 14 of 14 (up: a route between two of its bases); ZA2 to ZC1 14 of 14 (up), ZC2, ZC3, ZC4 13 of 14 (hold).
--        So, per direction, 16 up, 4 hold, 2 down, and the game actions route by route only (since 21 Oct: never a whole
--        base), one per direction that moves (since 26 Oct): ZB6's two set-back changes first, then the 18 directions that
--        move, From hub to dest then From dest to hub, economy; the 4 back directions that hold get none.
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
--        history's economy fare that day (255): index 85. ZW3 (business seats; migration 20261022030000, spec
--        docs/specs/2026-10-21-links-and-business-index.md §2) the same in both cabins: only the daily history holds its
--        days up to 21 Oct, economy at 255 on 20 and 21 Oct, business at 765 on 20 Oct with business passengers and at 900
--        on 21 Oct with none (no one paid it: not a baseline); its business index is 85 from the 20 Oct fare.
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
--      archived with no business fare in the daily history; since 22 Oct a business baseline only the daily history holds,
--      from a day with business passengers. (L1's ZB6, below, is the route at 100% against 110% with its two fix actions
--      at +10%.)
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
--  13. Per direction (since 26 Oct; spec docs/specs/2026-10-26-fare-ladder-per-direction.md §5), LP: one direction sold out
--      and the other at 80% (out up, back down); one direction under the minimum departures; a both-directions row read by
--      both; a direction's own row winning over an older both-directions row and losing to a newer one; the hold after a
--      step down on one direction only; under launch on one direction only; a set-back on one direction only; the capacity
--      hold and the rival pause holding both; the actions (one per direction, both classes ticked when the cabins agree,
--      set-backs first); fare_plan_status() seeing a direction's row by that direction's fares; capture_fare_actions()
--      matching a direction; and on the copy, each route and cabin's two directions at the route's level before the build.
--  14. The hold after a step up (since 26 Oct; migration 20261027000000_fare_ladder_up_hold.sql, spec
--      docs/specs/2026-10-26-fare-ladder-hold-after-step-up.md), LH: a direction stepped up 5 days before the Saturday
--      holds with its reason and no action; at 7 days it is judged; the hold after a step down keeps its 2 weeks; a revert
--      or a hold row doesn't hold; a both-directions up row holds both; held both ways, the more recent move's reason.
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
  insert into public.aircraft (world_id, airline_id, registration, aircraft_type_id, cabin_config_id, status, base_code, acquired)
  values (w, al, 'ZL-' || k, ty, cfg, 'active', hub, 'new') returning id into ac;
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

-- a level recorded on the fare plan (since 26 Oct with a direction, out or back; none for both directions)
create function pg_temp.ladder_row(w bigint, al bigint, r bigint, cabin text, level numeric, move text, on_day date, fare_from numeric default null,
                                   change numeric default null, dir text default null)
returns bigint language sql as $f$
  insert into public.fare_plan (world_id, airline_id, route_id, legacy_key, cabin_class, change_pct, fare_from, proposed_on, status, reason, level_pct, ladder_move,
                                direction)
  values (w, al, r, 'fl-test-' || r || '-' || cabin || '-' || on_day || coalesce('-' || dir, ''), cabin, change, fare_from, on_day, 'planned', 'test', level, move, dir)
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
  -- since 26 Oct: the direction, out or back (null for both), described
  assert col_description('public.fare_plan'::regclass, (select attnum from pg_attribute where attrelid = 'public.fare_plan'::regclass and attname = 'direction')) like '%out%back%both directions%',
    'fare_plan.direction has no description';
  begin
    insert into public.fare_plan (world_id, airline_id, status, direction)
    select a.world_id, a.id, 'planned', 'sideways' from public.airlines a join public.worlds w on w.id = a.world_id and w.is_default limit 1;
    assert false, 'fare_plan took a direction that isn''t out or back';
  exception when check_violation then null;
  end;
  begin
    insert into public.fare_plan (world_id, airline_id, status, ladder_move)
    select a.world_id, a.id, 'planned', 'sideways' from public.airlines a join public.worlds w on w.id = a.world_id and w.is_default limit 1;
    assert false, 'fare_plan took a ladder move that isn''t up, down or hold';
  exception when check_violation then null;
  end;
  assert (select s.description like '%taken away isn''t tracked%' and s.unit = 'days' from public.settings s
           where s.key = 'fare_ladder_capacity_hold_days' and s.airline_id is null order by s.world_id limit 1),
    'fare_ladder_capacity_hold_days doesn''t say a frequency taken away isn''t tracked, or isn''t in days';
  raise notice 'the seven fare ladder settings in each of the % world(s) (5 points, up at 100%%, down under 90%%, 5 departures, 2 weeks, cap 20 points, a new flight held 7 days), described; fare_plan.level_pct numeric(5,1), ladder_move (up, down or hold) and since 26 Oct direction (out or back) described', n_worlds;
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
                                'ZE9', 'ZEA', 'ZK1', 'ZK2', 'ZK3', 'ZK4', 'ZK5', 'ZK6', 'ZK7', 'ZK8', 'ZKA', 'ZW0', 'ZW1', 'ZW2', 'ZW3',
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
  -- ZW3, business seats: its days up to 21 Oct only in the daily history, both cabins (the business fare since 22 Oct);
  -- business at 765 (85% of 900) on 20 Oct with business passengers, at 900 on 21 Oct with none; in the week 255 and 765
  r := pg_temp.ladder_route(w, l6, 'ZW0', 'ZW3', 73, 14, 14, date '2026-09-30', ty, cj, 255, 14, 765, with_base => false);
  insert into public.route_days (world_id, airline_id, route_id, origin_code, dest_code, day, flights, passengers, seats, eco_fare_avg,
                                 eco_pax, eco_seats, bus_pax, bus_seats, bus_fare_avg)
  select w, l6, r, h.o, h.d, h.day, 1, 168 + h.bus_pax, 180, 255, 168, 168, h.bus_pax, 12, h.bus_fare
    from (values ('ZW0', 'ZW3', date '2026-10-20', 12, 765), ('ZW3', 'ZW0', date '2026-10-20', 12, 765),
                 ('ZW0', 'ZW3', date '2026-10-21', 0, 900), ('ZW3', 'ZW0', date '2026-10-21', 0, 900)) h(o, d, day, bus_pax, bus_fare);

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

-- each route and cabin of a ladder in one line: "move level>new (reason)". Since 26 Oct a row per direction: one line when
-- both directions say the same, else "out <line> / back <line>"; with dir, that direction's only
create function pg_temp.ladder_line(d jsonb, dest text, cabin text default 'economy', dir text default null) returns text language sql as $f$
  with x as (select x ->> 'direction' as dn, x ->> 'move' || ' ' || (x ->> 'level') || '>' || (x ->> 'new_level') || ' (' || (x ->> 'reason') || ')' as line
               from jsonb_array_elements(d -> 'routes') x
              where x ->> 'dest' = dest and x ->> 'cabin' = cabin and (dir is null or x ->> 'direction' = dir))
  select case when count(distinct x.line) = 1 then min(x.line) else string_agg(x.dn || ' ' || x.line, ' / ' order by x.dn = 'back') end from x
$f$;
-- a route's rows in one line, per direction and cabin: "out economy …; back economy …"
create function pg_temp.ladder_dirs(d jsonb, dest text) returns text language sql as $f$
  select string_agg((x ->> 'direction') || ' ' || (x ->> 'cabin') || ' ' || (x ->> 'move') || ' ' || (x ->> 'level') || '>' || (x ->> 'new_level')
                    || ' (' || (x ->> 'reason') || ')', '; ' order by o)
    from jsonb_array_elements(d -> 'routes') with ordinality t(x, o) where x ->> 'dest' = dest
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
  select x into e from jsonb_array_elements(d -> 'routes') x where x ->> 'dest' = 'ZK2' and x ->> 'direction' = 'back';
  assert e ->> 'departures' = '7' and e ->> 'sold_out' = '7' and not (e ->> 'to_plan')::boolean and not (e ->> 'new_route')::boolean
     and e ->> 'from' = 'ZK2' and e ->> 'to' = 'ZK1' and (e ->> 'load')::numeric = 100,
    'ZK2 back isn''t sold out 7 of 7 (load 100%) from ZK2 to ZK1 with nothing to put on the fare plan: ' || e::text;
  -- a route whose only rotation is new is still a new route; a flight added on the latest captured day holds too
  assert pg_temp.ladder_line(d, 'ZK3') = 'hold 100>100 (new route, launched 16 Jan)', 'ZK3: ' || pg_temp.ladder_line(d, 'ZK3');
  assert pg_temp.ladder_line(d, 'ZK8') = 'hold 110>110 (a flight added on 18 Jan: judged at its new size from 25 Jan)', 'ZK8: ' || pg_temp.ladder_line(d, 'ZK8');
  -- planned first: ZK4, on the fare plan this week, isn't held by anything
  assert pg_temp.ladder_line(d, 'ZK4') = 'up 110>115 (test)', 'ZK4, on the fare plan: ' || pg_temp.ladder_line(d, 'ZK4');
  -- the same route 8 days after its new rotation launched: it moves
  update public.rotations set launched_on = date '2030-01-11' where id = rot;
  d := private.fig_fare_ladder(l5, t);
  assert pg_temp.ladder_line(d, 'ZK2') = 'up 100>105 (sold out 7 of 7)', 'ZK2, its new rotation 8 days old: ' || pg_temp.ladder_line(d, 'ZK2');
  update public.rotations set launched_on = date '2030-01-16' where id = rot;
  raise notice 'a new frequency (spec part 1): a route sold out 7 of 7 each way with a rotation launched 3 days ago holds both directions ("a flight added on 16 Jan: judged at its new size from 23 Jan"); 8 days on it moves up; a route whose only rotation is new is still a new route; a move on the fare plan comes first';
end
$test$;

-- ---------------------------------------------------------------- 4. L5 and L6: the set-back changes and the fare index (spec part 3)
do $test$
declare l5 bigint := (select (v #>> '{}')::bigint from t_fl where k = 'l5'); l6 bigint := (select (v #>> '{}')::bigint from t_fl where k = 'l6');
  t timestamptz := (select (v #>> '{}')::timestamptz from t_fl where k = 't'); d jsonb; e jsonb; got text;
begin
  d := private.fig_fare_ladder(l5, t);
  -- each route and cabin: its index, whether it matches, and whether it is set back
  select string_agg(x ->> 'dest' || ' ' || (x ->> 'direction') || ' ' || (x ->> 'cabin') || ' ' || coalesce(x ->> 'fare_index', '—') || ' '
                    || coalesce(x ->> 'index_matches', '—') || ' ' || (x ->> 'fix'), '; ' order by o) into got
    from jsonb_array_elements(d -> 'routes') with ordinality t(x, o);
  assert got = 'ZK2 out economy 100.0 true false; ZK2 back economy 100.0 true false; ZK3 out economy 100.0 true false; ZK3 back economy 100.0 true false; '
            || 'ZK4 out economy 100.0 false false; ZK4 back economy 100.0 false false; ZK5 out economy 99.3 false true; ZK5 back economy 100.0 true false; '
            || 'ZK6 out economy 110.0 false false; ZK6 back economy 100.0 true false; ZK7 out economy 100.0 false true; ZK7 out business 100.0 false true; '
            || 'ZK7 back economy 100.0 false true; ZK7 back business 100.0 false true; ZK8 out economy 100.0 false false; ZK8 back economy 100.0 false false; '
            || 'ZKA out economy 100.0 true false; ZKA out business — — false; ZKA back economy 100.0 true false; ZKA back business — — false',
    'L5''s fare indexes and set-backs are ' || got;
  -- each flight compared, not the day's average: ZK5 out's 99.3 is within a point, its flight at 294 (98%) isn't; since 26
  -- Oct only that direction is set back, its flights back all at 300
  select x into e from jsonb_array_elements(d -> 'routes') x where x ->> 'dest' = 'ZK5' and x ->> 'direction' = 'out';
  assert e ->> 'fix_reason' = 'captured fare at 98%, level 100%' and e ->> 'move' = 'up' and e ->> 'latest_on' = '2030-01-18',
    'ZK5 out isn''t set back for its flight at 98% (its move still up): ' || e::text;
  -- the economy's baseline from the daily history; no business index once its first days are archived
  select x into e from jsonb_array_elements(d -> 'routes') x where x ->> 'dest' = 'ZKA' and x ->> 'cabin' = 'economy' and x ->> 'direction' = 'back';
  assert e ->> 'baseline_on' = '2029-11-02' and (e ->> 'baseline_fare')::numeric = 300, 'ZKA''s economy baseline isn''t the daily history''s 300 on 2 Nov: ' || e::text;
  select x into e from jsonb_array_elements(d -> 'routes') x where x ->> 'dest' = 'ZKA' and x ->> 'cabin' = 'business' and x ->> 'direction' = 'out';
  assert e ->> 'baseline_fare' is null and (e ->> 'latest_fare')::numeric = 990, 'ZKA''s business has a baseline, though its first days are gone: ' || e::text;
  -- the set-back changes first: ZK5 out only at +0% (100), ZK7's both cabins at +10% in one action each way; then the
  -- week's moves
  select string_agg(x ->> 'n' || '. ' || (x ->> 'text') || ' [' || (x ->> 'reason') || ']', ' | ' order by (x ->> 'n')::int) into got
    from jsonb_array_elements(d -> 'actions') x where (x ->> 'fix')::boolean;
  assert got = '1. From ZK1 to ZK5: +0% of the default price, economy [captured fare at 98%, level 100%] | '
            || '2. From ZK1 to ZK7: +10% of the default price, economy and business [economy: captured fare at 100%, level 110%; business: captured fare at 100%, level 110%] | '
            || '3. From ZK7 to ZK1: +10% of the default price, economy and business [economy: captured fare at 100%, level 110%; business: captured fare at 100%, level 110%]',
    'L5''s set-back changes are ' || coalesce(got, 'none');
  assert (select min((x ->> 'n')::int) from jsonb_array_elements(d -> 'actions') x where not (x ->> 'fix')::boolean) = 4
     and (d ->> 'off_level')::int = 3 and jsonb_array_length(d -> 'actions') > 3,
    'the week''s moves don''t follow the 3 set-back changes, or off_level (directions) isn''t 3: ' || (d ->> 'off_level');
  -- none for a route on the fare plan this week (ZK4), a new route (ZK6), or one not captured since its newest rotation (ZK8)
  assert not exists (select 1 from jsonb_array_elements(d -> 'actions') x where (x ->> 'fix')::boolean and x ->> 'route' in ('ZK1–ZK4', 'ZK1–ZK6', 'ZK1–ZK8')),
    'a set-back change for a planned, new or not yet captured route: ' || (d -> 'actions')::text;

  -- L6 (launch 85%): the baseline of 21 Oct 2026, Ryanair's early cuts and the daily history
  d := private.fig_fare_ladder(l6, t);
  select string_agg(x ->> 'dest' || ' ' || (x ->> 'direction') || ' ' || (x ->> 'fare_index') || ' ' || (x ->> 'index_matches') || ' ' || (x ->> 'baseline_on') || ' '
                    || trim_scale((x ->> 'baseline_fare')::numeric), '; ' order by o) into got
    from jsonb_array_elements(d -> 'routes') with ordinality t(x, o) where x ->> 'dest' <> 'ZW3';
  assert got = 'ZW1 out 85.0 true 2026-10-20 255; ZW1 back 85.0 true 2026-10-20 255; ZW2 out 85.0 true 2026-10-21 255; ZW2 back 85.0 true 2026-10-21 255'
     and (d ->> 'off_level')::int = 0 and d #>> '{settings,baseline_day}' = '2026-10-21',
    'L6''s routes aren''t at 85 from their fares of 20 and 21 Oct 2026: ' || coalesce(got, 'none');
  -- ZW3 (since 22 Oct): both cabins' baselines from the daily history alone, business's from 20 Oct (765), the day with
  -- business passengers, not 21 Oct (900, no one paid it); both at 85, nothing set back
  select string_agg(x ->> 'cabin' || ' ' || (x ->> 'fare_index') || ' ' || (x ->> 'index_matches') || ' ' || (x ->> 'baseline_on') || ' '
                    || trim_scale((x ->> 'baseline_fare')::numeric) || ' ' || (x ->> 'fix'), '; ' order by x ->> 'cabin') into got
    from jsonb_array_elements(d -> 'routes') x where x ->> 'dest' = 'ZW3' and x ->> 'direction' = 'back';
  assert got = 'business 85.0 true 2026-10-20 765 false; economy 85.0 true 2026-10-21 255 false'
     and pg_temp.ladder_line(d, 'ZW3') = pg_temp.ladder_line(d, 'ZW3', 'economy', 'out'),
    'ZW3''s baselines aren''t the daily history''s, business 765 on 20 Oct and economy 255 on 21 Oct, both at 85: ' || coalesce(got, 'none');
  raise notice 'set back (spec part 3): a route at 100%% against 110%% gets two fix actions at +10%% (both classes in one action each way when both cabins are off), first in the list with the reason; since 26 Oct a direction off on its own gets one; none for one on the fare plan this week, a new route, or one not captured since its newest rotation launched; each flight compared (one at 98%% among four, the day''s average 99.5); a cut early in October read from its fare of 20 Oct 2026 (85, not 72), the daily history''s fare of 21 Oct, no business index once its first days are archived with no business fare in the daily history, and since 22 Oct a business baseline from the daily history alone (85 from 20 Oct, a day with no business passengers skipped)';
end
$test$;

-- ---------------------------------------------------------------- 5. L1: two bases, the moves and the game actions
do $test$
declare l1 bigint := (select (v #>> '{}')::bigint from t_fl where k = 'l1'); t timestamptz := (select (v #>> '{}')::timestamptz from t_fl where k = 't');
  d jsonb; got text; want text;
begin
  d := private.fig_fare_ladder(l1, t);
  assert d ->> 'week_of' = '2030-01-19', 'this Saturday isn''t 19 Jan: ' || (d ->> 'week_of');
  assert (select count(*) from jsonb_array_elements(d -> 'routes')) = 22 and not exists (select 1 from jsonb_array_elements(d -> 'routes') x where x ->> 'cabin' <> 'economy'),
    'L1 hasn''t its 11 routes in economy only, each both ways: ' || (d -> 'routes')::text;
  -- the rows' order: hub, dest, out before back (since 26 Oct)
  assert (select string_agg(x ->> 'hub' || '-' || (x ->> 'dest') || ' ' || (x ->> 'direction') || ' ' || (x ->> 'from') || '>' || (x ->> 'to'), ', ' order by o)
            from jsonb_array_elements(d -> 'routes') with ordinality t(x, o) where o <= 4)
       = 'ZA1-ZA2 out ZA1>ZA2, ZA1-ZA2 back ZA2>ZA1, ZA1-ZB1 out ZA1>ZB1, ZA1-ZB1 back ZB1>ZA1',
    'L1''s rows aren''t by hub, dest and direction, out first, with their airports that way round: ' || (d -> 'routes')::text;
  select string_agg(x ->> 'dest' || ' ' || pg_temp.ladder_line(d, x ->> 'dest'), '; ' order by x ->> 'hub', x ->> 'dest') into got
    from jsonb_array_elements(d -> 'routes') x where x ->> 'direction' = 'out';
  want := 'ZA2 up 100>105 (sold out 7 of 7); ZB1 up 100>105 (sold out 7 of 7); ZB2 up 100>105 (sold out 7 of 7); ZB3 up 100>105 (sold out 7 of 7); '
       || 'ZB4 up 100>105 (sold out 7 of 7); ZB5 out up 100>105 (sold out 7 of 7) / back hold 100>100 (sold out 6 of 7, at launch (100%)); '
       || 'ZB6 down 110>105 (sold out 5 of 7); ZC1 up 100>105 (sold out 7 of 7); '
       || 'ZC2 out up 100>105 (sold out 7 of 7) / back hold 100>100 (sold out 6 of 7, at launch (100%)); '
       || 'ZC3 out up 100>105 (sold out 7 of 7) / back hold 100>100 (sold out 6 of 7, at launch (100%)); '
       || 'ZC4 out up 100>105 (sold out 7 of 7) / back hold 100>100 (sold out 6 of 7, at launch (100%))';
  assert got = want, 'L1''s moves are ' || got;
  assert d -> 'moves' = '{"up": 16, "hold": 4, "down": 2, "jumps": 0, "decisions": 0}'::jsonb, 'L1''s moves aren''t 16 up, 4 hold, 2 down (directions): ' || (d -> 'moves')::text;
  assert (d ->> 'to_plan')::int = 18 and (d ->> 'planned')::int = 0, 'Put on the fare plan doesn''t write the 18 changed levels: ' || (d ->> 'to_plan');
  -- the steps, the departures and the share, each direction's
  assert (select bool_and(x ->> 'departures' = '7' and x ->> 'sold_out' = '5' and (x ->> 'sold_out_share')::numeric = 71.4 and x ->> 'steps' = '2' and x ->> 'new_steps' = '1'
                 and (x ->> 'change_pct')::numeric = -4.5 and (x ->> 'recorded')::boolean and (x ->> 'load')::numeric = 94.3) and count(*) = 2
            from jsonb_array_elements(d -> 'routes') x where x ->> 'dest' = 'ZB6'),
    'ZB6 isn''t 5 of 7 each way (71.4%, load 94.3%), 2 steps above launch going to 1 (−4.5%), from the fare plan: ' || (select string_agg(x::text, ' ') from jsonb_array_elements(d -> 'routes') x where x ->> 'dest' = 'ZB6');
  -- the fare index: every captured fare 300 against a first fare of 300, so 100 everywhere; ZB6 recorded at 110 doesn't
  -- match it, so it is set back to 110 (spec docs/specs/2026-10-21-frequencies-and-fares.md §3), its move as it was
  assert (select string_agg(x ->> 'dest' || ' ' || (x ->> 'direction'), ',' order by o) from jsonb_array_elements(d -> 'routes') with ordinality t(x, o) where not (x ->> 'index_matches')::boolean) = 'ZB6 out,ZB6 back'
     and (select bool_and((x ->> 'fare_index')::numeric = 100) from jsonb_array_elements(d -> 'routes') x where x ->> 'dest' = 'ZB6'),
    'only ZB6 (index 100 against 110) should be flagged, both ways: ' || (d -> 'routes')::text;
  assert (select string_agg(x ->> 'dest' || ' ' || (x ->> 'direction') || ' ' || (x ->> 'fix_reason') || ' ' || (x ->> 'move'), ',' order by o)
            from jsonb_array_elements(d -> 'routes') with ordinality t(x, o) where (x ->> 'fix')::boolean)
       = 'ZB6 out captured fare at 100%, level 110% down,ZB6 back captured fare at 100%, level 110% down' and (d ->> 'off_level')::int = 2,
    'only ZB6 should be set back, both ways ("captured fare at 100%, level 110%"), its move still down: ' || (d -> 'routes')::text;
  assert (select bool_and((x ->> 'baseline_fare')::numeric = 300 and x ->> 'baseline_on' = '2029-12-02' and (x ->> 'latest_fare')::numeric = 300 and x ->> 'latest_on' = '2030-01-18')
            from jsonb_array_elements(d -> 'routes') x where x ->> 'dest' = 'ZB6'),
    'ZB6''s baseline isn''t 300 on 2 Dec (its first captured day), its latest 300 on 18 Jan: ' || (select string_agg(x::text, ' ') from jsonb_array_elements(d -> 'routes') x where x ->> 'dest' = 'ZB6');
  -- route by route only (21 Oct): ZB6 set back first, then each direction that moves (since 26 Oct), in the rows' order;
  -- no base action, none for a hold
  select string_agg(x ->> 'n' || '. ' || (x ->> 'text'), ' | ' order by (x ->> 'n')::int) into got from jsonb_array_elements(d -> 'actions') x;
  want := '1. From ZA1 to ZB6: +10% of the default price, economy | 2. From ZB6 to ZA1: +10% of the default price, economy | '
       || '3. From ZA1 to ZA2: +5% of the default price, economy | 4. From ZA2 to ZA1: +5% of the default price, economy | '
       || '5. From ZA1 to ZB1: +5% of the default price, economy | 6. From ZB1 to ZA1: +5% of the default price, economy | '
       || '7. From ZA1 to ZB2: +5% of the default price, economy | 8. From ZB2 to ZA1: +5% of the default price, economy | '
       || '9. From ZA1 to ZB3: +5% of the default price, economy | 10. From ZB3 to ZA1: +5% of the default price, economy | '
       || '11. From ZA1 to ZB4: +5% of the default price, economy | 12. From ZB4 to ZA1: +5% of the default price, economy | '
       || '13. From ZA1 to ZB5: +5% of the default price, economy | '
       || '14. From ZA1 to ZB6: +5% of the default price, economy | 15. From ZB6 to ZA1: +5% of the default price, economy | '
       || '16. From ZA2 to ZC1: +5% of the default price, economy | 17. From ZC1 to ZA2: +5% of the default price, economy | '
       || '18. From ZA2 to ZC2: +5% of the default price, economy | 19. From ZA2 to ZC3: +5% of the default price, economy | '
       || '20. From ZA2 to ZC4: +5% of the default price, economy';
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
  raise notice 'L1, per direction: 16 up, 4 hold, 2 down; 18 rows to put on the fare plan; ZB6''s index (100 against 110) flagged both ways, and its 2 set-back changes at +10%% first; then 18 game actions, one per direction that moves (ZA1–ZA2, between the two bases, like any other; ZB5 and ZC2 to ZC4 out only), economy, none for the 4 back directions that hold, no base action';
end
$test$;

-- ---------------------------------------------------------------- 6. L2: Ryanair's 85% and its cap
do $test$
declare l2 bigint := (select (v #>> '{}')::bigint from t_fl where k = 'l2'); t timestamptz := (select (v #>> '{}')::timestamptz from t_fl where k = 't');
  d jsonb; got text;
begin
  d := private.fig_fare_ladder(l2, t);
  assert d #>> '{settings,launch_pct}' = '85' and d #>> '{settings,cap_pct}' = '105', 'L2 doesn''t launch at 85% with its cap at 105%: ' || (d -> 'settings')::text;
  select string_agg(x ->> 'dest' || ' ' || pg_temp.ladder_line(d, x ->> 'dest'), '; ' order by x ->> 'dest') into got from jsonb_array_elements(d -> 'routes') x where x ->> 'direction' = 'out';
  assert got = 'ZS1 up 85>90 (sold out 7 of 7); ZS2 hold 105>105 (sold out 7 of 7, capped at 105%); ZS3 up 102>105 (sold out 7 of 7, up to the 105% cap); ZS4 up 90>95 (sold out 7 of 7)',
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
  assert (select string_agg(x ->> 'dest' || ' ' || (x ->> 'fare_index'), ', ' order by o) from jsonb_array_elements(d -> 'routes') with ordinality t(x, o))
       = 'ZS1 85.0, ZS1 85.0, ZS2 105.0, ZS2 105.0, ZS3 102.0, ZS3 102.0, ZS4 90.0, ZS4 90.0' and (d ->> 'off_level')::int = 0,
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
  -- contested is the pair's, the same on both directions' rows
  select string_agg(x ->> 'dest' || ' ' || pg_temp.ladder_line(d, x ->> 'dest') || case when (x ->> 'contested')::boolean then ' contested' else '' end, '; ' order by o)
    into got from jsonb_array_elements(d -> 'routes') with ordinality t(x, o);
  assert got = 'ZU1 down 62>60 (sold out 5 of 7, down to the 60% floor) contested; ZU1 down 62>60 (sold out 5 of 7, down to the 60% floor) contested; '
            || 'ZU2 hold 60>60 (sold out 5 of 7, at the 60% floor) contested; ZU2 hold 60>60 (sold out 5 of 7, at the 60% floor) contested; '
            || 'ZU3 down 60>55 (sold out 5 of 7, down to launch (55%)); ZU3 down 60>55 (sold out 5 of 7, down to launch (55%)); '
            || 'ZU4 hold 55>55 (sold out 5 of 7, at launch (55%)); ZU4 hold 55>55 (sold out 5 of 7, at launch (55%)); '
            || 'ZU5 down 62>60 (sold out 5 of 7, down to the 60% floor) contested; ZU5 down 62>60 (sold out 5 of 7, down to the 60% floor) contested',
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
  assert pg_temp.ladder_line(d, 'ZE1') = 'hold 120>120 (sold out 7 of 7, capped at 120%)', 'ZE1 economy: ' || pg_temp.ladder_line(d, 'ZE1');
  assert pg_temp.ladder_line(d, 'ZE1', 'business') = 'up 100>105 (sold out 7 of 7)', 'ZE1 business, a cabin of its own: ' || pg_temp.ladder_line(d, 'ZE1', 'business');
  assert pg_temp.ladder_line(d, 'ZE2') = 'hold 105>105 (held after a step down on 12 Jan)', 'ZE2: ' || pg_temp.ladder_line(d, 'ZE2');
  assert pg_temp.ladder_line(d, 'ZE2', 'business') = 'out up 100>105 (sold out 7 of 7) / back hold 100>100 (sold out 6 of 7, at launch (100%))',
    'ZE2 business, 13 of 14 (out 7 of 7, back 6 of 7): ' || pg_temp.ladder_line(d, 'ZE2', 'business');
  assert pg_temp.ladder_line(d, 'ZE3') = 'up 105>110 (sold out 7 of 7)', 'ZE3, two weeks after its step down: ' || pg_temp.ladder_line(d, 'ZE3');
  assert pg_temp.ladder_line(d, 'ZE4') = 'hold 100>100 (new route, launched 15 Jan)', 'ZE4: ' || pg_temp.ladder_line(d, 'ZE4');
  assert pg_temp.ladder_line(d, 'ZE5') = 'hold 100>100 (2 departures captured, needs 5)', 'ZE5, 4 departures, 2 each way: ' || pg_temp.ladder_line(d, 'ZE5');
  assert pg_temp.ladder_line(d, 'ZE6') = 'up 100>105 (test)', 'ZE6, on the fare plan this Saturday: ' || pg_temp.ladder_line(d, 'ZE6');
  assert pg_temp.ladder_line(d, 'ZT1') = 'hold 100>100 (no departures captured)', 'ZU5–ZT1, no flights captured: ' || coalesce(pg_temp.ladder_line(d, 'ZT1'), 'none');
  select x into e from jsonb_array_elements(d -> 'routes') x where x ->> 'dest' = 'ZE6' and x ->> 'cabin' = 'economy' and x ->> 'direction' = 'back';
  assert (e ->> 'planned')::boolean and not (e ->> 'to_plan')::boolean and e ->> 'plan_id' is not null, 'ZE6 back isn''t planned already (a both-directions row): ' || e::text;
  select x into e from jsonb_array_elements(d -> 'routes') x where x ->> 'dest' = 'ZE2' and x ->> 'cabin' = 'economy' and x ->> 'direction' = 'back';
  assert (e ->> 'to_plan')::boolean, 'ZE2 back''s hold after a step down has nothing to record: ' || e::text;
  select string_agg(x ->> 'dest' || ' ' || (x ->> 'direction') || ' ' || (x ->> 'cabin'), ', ' order by o) into got
    from jsonb_array_elements(d -> 'routes') with ordinality t(x, o) where (x ->> 'to_plan')::boolean;
  assert got = 'ZE1 out business, ZE1 back business, ZE2 out economy, ZE2 out business, ZE2 back economy, ZE3 out economy, ZE3 out business, ZE3 back economy, '
            || 'ZE6 out business, ZE7 out economy, ZE7 out business, ZE7 back economy, ZE8 out economy, ZE8 out business, ZE8 back business, '
            || 'ZE9 out economy, ZE9 out business, ZE9 back economy, ZE9 back business, ZEA out economy, ZEA out business, ZEA back economy, ZEA back business',
    'Put on the fare plan would write ' || got;
  assert pg_temp.ladder_line(d, 'ZE9') = 'up 100>105 (sold out 7 of 7)' and pg_temp.ladder_line(d, 'ZE9', 'business') = 'up 100>105 (sold out 7 of 7)',
    'ZE9, both cabins to 105: ' || pg_temp.ladder_line(d, 'ZE9') || ' / ' || pg_temp.ladder_line(d, 'ZE9', 'business');
  assert pg_temp.ladder_line(d, 'ZEA') = 'up 105>110 (sold out 7 of 7)' and pg_temp.ladder_line(d, 'ZEA', 'business') = 'up 100>105 (sold out 7 of 7)',
    'ZEA, economy to 110 and business to 105: ' || pg_temp.ladder_line(d, 'ZEA') || ' / ' || pg_temp.ladder_line(d, 'ZEA', 'business');
  -- the game actions, route by route (21 Oct), one per direction (26 Oct): one cabin moving gets its own; both to the same
  -- level, one with both classes (ZE9, and ZE6 out, its economy on the fare plan this week and its business sold out); to
  -- different levels, one per cabin, economy first (ZEA). ZE1's capped economy, held ZE2 economy, new ZE4, ZE5 with 2
  -- departures each way and the holds get none
  select string_agg(x ->> 'n' || '. ' || (x ->> 'text'), ' | ' order by (x ->> 'n')::int) into got from jsonb_array_elements(d -> 'actions') x;
  assert got = '1. From ZD1 to ZE1: +5% of the default price, business | 2. From ZE1 to ZD1: +5% of the default price, business | '
            || '3. From ZD1 to ZE2: +5% of the default price, business | '
            || '4. From ZD1 to ZE3: +10% of the default price, economy | 5. From ZD1 to ZE3: +5% of the default price, business | '
            || '6. From ZE3 to ZD1: +10% of the default price, economy | '
            || '7. From ZD1 to ZE6: +5% of the default price, economy and business | 8. From ZE6 to ZD1: +5% of the default price, economy | '
            || '9. From ZD1 to ZE7: +10% of the default price, economy | 10. From ZD1 to ZE7: +5% of the default price, business | '
            || '11. From ZE7 to ZD1: +0% of the default price, economy | '
            || '12. From ZD1 to ZE8: +5% of the default price, economy | 13. From ZD1 to ZE8: +10% of the default price, business | '
            || '14. From ZE8 to ZD1: +0% of the default price, business | '
            || '15. From ZD1 to ZE9: +5% of the default price, economy and business | 16. From ZE9 to ZD1: +5% of the default price, economy and business | '
            || '17. From ZD1 to ZEA: +10% of the default price, economy | 18. From ZD1 to ZEA: +5% of the default price, business | '
            || '19. From ZEA to ZD1: +10% of the default price, economy | 20. From ZEA to ZD1: +5% of the default price, business',
    'L4''s game actions are ' || got;
  select string_agg(x ->> 'n' || ' ' || (x -> 'classes')::text, ', ' order by (x ->> 'n')::int) into got from jsonb_array_elements(d -> 'actions') x where (x ->> 'n')::int >= 15;
  assert got = '15 ["economy", "business"], 16 ["economy", "business"], 17 ["economy"], 18 ["business"], 19 ["economy"], 20 ["business"]',
    'L4''s actions'' classes are ' || got;
  assert (select x ->> 'route' = 'ZD1–ZE9' and x ->> 'from' = 'ZE9' and x ->> 'to' = 'ZD1' and x -> 'level' = '105'::jsonb and x ->> 'sign' = '+' and x -> 'pct' = '5'::jsonb
            from jsonb_array_elements(d -> 'actions') x where (x ->> 'n')::int = 16),
    'action 16 isn''t ZD1–ZE9 from ZE9 to ZD1 at 105 (+5): ' || (d -> 'actions' -> 15)::text;
  -- the fare index: its first fare 300 (2 Dec, the day after it launched), 315 now, launch 100 → 105, as recorded
  select x into e from jsonb_array_elements(d -> 'routes') x where x ->> 'dest' = 'ZE7' and x ->> 'cabin' = 'economy' and x ->> 'direction' = 'out';
  assert (e ->> 'fare_index')::numeric = 105 and (e ->> 'index_matches')::boolean and e ->> 'baseline_on' = '2029-12-02' and (e ->> 'baseline_fare')::numeric = 300
     and (e ->> 'latest_fare')::numeric = 315, 'ZE7''s fare index isn''t 105 (its first fare 300 on 2 Dec, 315 now), matching its level: ' || e::text;
  assert d -> 'moves' = '{"up": 21, "hold": 21, "down": 2, "jumps": 0, "decisions": 0}'::jsonb, 'L4''s moves (directions): ' || (d -> 'moves')::text;
  assert (d ->> 'off_level')::int = 0 and not exists (select 1 from jsonb_array_elements(d -> 'routes') x where not (x ->> 'index_matches')::boolean),
    'L4 has a route off its level, every fare at it: ' || (d -> 'routes')::text;
  -- the rival pause is built (competition analysis, spec §2): the note that said it waited for step 4 is gone
  assert jsonb_array_length(d -> 'notes') = 1 and d ->> 'notes' not like '%step 4%' and d ->> 'notes' like '%fare index%',
    'the notes still say rivals'' pauses wait for step 4, or lost the fare index''s: ' || (d -> 'notes')::text;
  raise notice 'L4, per direction: economy capped at 120%% while business climbs; held 2 weeks after a step down (with a hold to record), then climbs; a new route and 2 departures each way hold; this Saturday''s move already on the fare plan, both ways; the fare index 105 from 300 to 315; 20 game actions, one per direction and level: one cabin moving, both cabins to 105 (ZE9: both classes), to 110 and 105 (ZEA: one per cabin), none for the capped, held, new and few';
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
  select string_agg(x ->> 'dest' || ' ' || pg_temp.ladder_line(d, x ->> 'dest'), '; ' order by x ->> 'dest') into got from jsonb_array_elements(d -> 'routes') x where x ->> 'direction' = 'out';
  assert got = 'ZQ1 hold 100>100 (rival Quest Air started here on 16 Jan: paused until 23 Jan); '
            || 'ZQ2 hold 100>100 (rival Quest Air added 7 a week here on 16 Jan: paused until 23 Jan); '
            || 'ZQ3 up 100>105 (sold out 7 of 7); ZQ4 up 100>105 (sold out 7 of 7); '
            || 'ZQ5 hold 100>100 (a flight added on 16 Jan: judged at its new size from 23 Jan)',
    'L7''s moves are ' || got;
  assert (select string_agg(x ->> 'route', ',' order by (x ->> 'n')::int) from jsonb_array_elements(d -> 'actions') x) = 'ZQ0–ZQ3,ZQ0–ZQ3,ZQ0–ZQ4,ZQ0–ZQ4',
    'a paused route has a game action, or a moving one hasn''t: ' || (d -> 'actions')::text;
  assert (select string_agg(x ->> 'dest' || ' ' || (x ->> 'direction'), ',' order by o) from jsonb_array_elements(d -> 'routes') with ordinality t(x, o) where (x ->> 'to_plan')::boolean)
       = 'ZQ3 out,ZQ3 back,ZQ4 out,ZQ4 back',
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

-- ---------------------------------------------------------------- 12. under launch (spec docs/specs/2026-10-23-fare-ladder-under-launch.md)
-- Migration 20261023100000_fare_ladder_under_launch.sql. In the same world, at the same moment T (Saturday 19 Jan 2030,
-- 12:00 UTC): the window is the 14 days before T. Three more of our airlines, economy only, every route flown since
-- 1 Nov 2029, an out (14:00) and back (18:00) a day, its economy load and fare as said (passengers = 180 × load), so
-- revenue a flight = passengers × fare; the jumps recorded with fare_from 300 (or 240 for the second), each seen the day
-- its fare first shows (fare_plan_status()'s rule). No route has a fare index (no baseline captured in its first days).
--   L8 (launch 100%, the world's levels [80, 60]):
--     ZV1 41% full for 14 days at launch: jumps to 80 ("41% full over 14 days at launch: to 80% for 2 weeks");
--     ZV2 85% full: no jump (holds at launch as before);
--     ZV3 50% full, 9 flights in the 14 days (5 in the last 7): waits ("9 flights in 14 days, needs 10 to jump");
--     ZV4 jumped on 12 Jan: holds ("at 80% since 12 Jan: judged on 26 Jan");
--     ZV5 jumped on 5 Jan, 60% full at 240 (25,920 a flight) against 40% at 300 (21,600) before: paid off, holds, recorded;
--     ZV6 jumped on 8 Dec, judged paid on 22 Dec (a hold recorded): 60% full, so it only climbs or holds;
--     ZV7 the same, sold out in the last 7 days: climbs 80 → 85 normally;
--     ZV8 jumped on 5 Jan, 40% full at 240 (17,280) against 21,600: jumps to 60;
--     ZV9 jumped on 22 Dec and to 60 on 5 Jan, 38% full at 180 (12,240) against 21,600: back to launch, decide;
--     ZVA the same, 50% full at 180 (16,200) against 25% at 300 (13,500): paid but under 60% full, holds at 60, decide;
--     ZVB at 105 since 22 Dec, 50% full: down 5 points to launch (100), never under it.
--   L9 (launch 85%, as Ryanair, the world's levels): ZY1 41% full: jumps to 80.
--   L10 (launch 85%, its own levels [75, 60], as Ryanair's row): ZX1 41% full: jumps to 75.
-- Then: a jump put on the fare plan this Saturday keeps its kind and capture_fare_actions() lists it with its plan row;
-- the settings and the fare plan's new moves; L3 (launch 55%) has no level under its launch to jump to.
-- Since 26 Oct each direction is judged on its own flights: every route here flies the same each way, so both directions
-- move alike (the counts are directions, the windows 14 flights each way), except ZV3, flown out only: its back direction
-- has no departures.

-- a day by day out and back from d0 to d1 (not included): `legs` a day (1: out only), at `load`% full in economy and `fare`
create function pg_temp.ul_days(w bigint, al bigint, hub text, dest text, k int, d0 date, d1 date, load numeric, fare numeric, legs int default 2)
returns void language sql as $f$
  insert into public.game_flights (world_id, airline_id, game_date, flight_no, origin_code, dest_code, dep_local, dep_at, registration,
                                   eco_pax, eco_seats, eco_pct, eco_fare, loads_captured_at)
  select w, al, d::date, 5000 + k * 2 + i, case when i = 0 then hub else dest end, case when i = 0 then dest else hub end,
         case when i = 0 then '14:00' else '18:00' end, d::date::timestamp at time zone 'UTC' + make_interval(hours => 14 + i * 4),
         'ZL-' || k, round(180 * load / 100), 180, load, fare, timestamptz '2030-01-19 11:00:00+00'
    from generate_series(d0, d1 - 1, interval '1 day') d cross join generate_series(0, legs - 1) i
$f$;

do $setup$
declare w bigint := (select (v #>> '{}')::bigint from t_fl where k = 'w');
  g bigint; ty bigint; cy bigint; l8 bigint; l9 bigint; l10 bigint; r bigint;
begin
  perform set_config('equinox.actor', 'claude', true), set_config('equinox.actor_detail', 'fare ladder under launch test', true);
  select x.id into g from public.groups x where x.world_id = w and x.kind = 'ours';
  select x.id into ty from public.aircraft_types x where x.world_id = w and x.name = 'LADDER TEST TYPE';
  select x.id into cy from public.cabin_configs x where x.world_id = w and x.code = 'LAD-Y';
  insert into public.airports (code, utc_offset)
  select c, 0 from unnest(array['ZV0', 'ZV1', 'ZV2', 'ZV3', 'ZV4', 'ZV5', 'ZV6', 'ZV7', 'ZV8', 'ZV9', 'ZVA', 'ZVB', 'ZY0', 'ZY1', 'ZX0', 'ZX1']) c
  on conflict (code) do update set utc_offset = excluded.utc_offset;
  insert into public.airlines (world_id, group_id, game_id, planner_name, public_name, iata_code, home_airport_code, active, position) values
    (w, g, 990308, 'Ladder Eight', 'L Eight', 'L8', 'ZV0', true, 8),
    (w, g, 990309, 'Ladder Nine', 'L Nine', 'L9', 'ZY0', true, 9),
    (w, g, 990310, 'Ladder Ten', 'L Ten', 'LX', 'ZX0', true, 10);
  select x.id into l8 from public.airlines x where x.world_id = w and x.iata_code = 'L8';
  select x.id into l9 from public.airlines x where x.world_id = w and x.iata_code = 'L9';
  select x.id into l10 from public.airlines x where x.world_id = w and x.iata_code = 'LX';
  insert into public.airline_bases (world_id, airline_id, airport_code, role, is_main, position) values
    (w, l8, 'ZV0', 'hub', true, 1), (w, l9, 'ZY0', 'hub', true, 1), (w, l10, 'ZX0', 'hub', true, 1);
  insert into public.settings (world_id, airline_id, key, value, unit, description) values
    (w, l9, 'fare_launch_pct', '85'::jsonb, '% of standard', 'test: launches at 85%, as Ryanair'),
    (w, l10, 'fare_launch_pct', '85'::jsonb, '% of standard', 'test: launches at 85%, as Ryanair'),
    (w, l10, 'fare_under_launch_levels', '[75, 60]'::jsonb, '% of default price', 'test: its own jump levels, as Ryanair''s row');

  -- ZV1: 41% full for 14 days at launch
  r := pg_temp.ladder_route(w, l8, 'ZV0', 'ZV1', 91, 0, 0, date '2029-11-01', ty, cy, with_base => false);
  perform pg_temp.ul_days(w, l8, 'ZV0', 'ZV1', 91, date '2030-01-05', date '2030-01-19', 41, 300);
  insert into t_fl values ('zv1', to_jsonb(r));
  -- ZV2: 85% full
  r := pg_temp.ladder_route(w, l8, 'ZV0', 'ZV2', 92, 0, 0, date '2029-11-01', ty, cy, with_base => false);
  perform pg_temp.ul_days(w, l8, 'ZV0', 'ZV2', 92, date '2030-01-05', date '2030-01-19', 85, 300);
  -- ZV3: 50% full, 9 flights in the 14 days, 5 of them in the last 7
  r := pg_temp.ladder_route(w, l8, 'ZV0', 'ZV3', 93, 0, 0, date '2029-11-01', ty, cy, with_base => false);
  perform pg_temp.ul_days(w, l8, 'ZV0', 'ZV3', 93, date '2030-01-08', date '2030-01-12', 50, 300, 1);
  perform pg_temp.ul_days(w, l8, 'ZV0', 'ZV3', 93, date '2030-01-13', date '2030-01-18', 50, 300, 1);
  -- ZV4: jumped on 12 Jan, holding
  r := pg_temp.ladder_route(w, l8, 'ZV0', 'ZV4', 94, 0, 0, date '2029-11-01', ty, cy, with_base => false);
  perform pg_temp.ul_days(w, l8, 'ZV0', 'ZV4', 94, date '2029-12-29', date '2030-01-12', 40, 300);
  perform pg_temp.ul_days(w, l8, 'ZV0', 'ZV4', 94, date '2030-01-12', date '2030-01-19', 40, 240);
  perform pg_temp.ladder_row(w, l8, r, 'economy', 80, 'jump', date '2030-01-12', 300, -20);
  -- ZV5: jumped on 5 Jan, paid off
  r := pg_temp.ladder_route(w, l8, 'ZV0', 'ZV5', 95, 0, 0, date '2029-11-01', ty, cy, with_base => false);
  perform pg_temp.ul_days(w, l8, 'ZV0', 'ZV5', 95, date '2029-12-22', date '2030-01-05', 40, 300);
  perform pg_temp.ul_days(w, l8, 'ZV0', 'ZV5', 95, date '2030-01-05', date '2030-01-19', 60, 240);
  perform pg_temp.ladder_row(w, l8, r, 'economy', 80, 'jump', date '2030-01-05', 300, -20);
  -- ZV6 and ZV7: jumped on 8 Dec, judged paid on 22 Dec; ZV7 sold out in the last 7 days
  r := pg_temp.ladder_route(w, l8, 'ZV0', 'ZV6', 96, 0, 0, date '2029-11-01', ty, cy, with_base => false);
  perform pg_temp.ul_days(w, l8, 'ZV0', 'ZV6', 96, date '2029-11-24', date '2029-12-08', 40, 300);
  perform pg_temp.ul_days(w, l8, 'ZV0', 'ZV6', 96, date '2029-12-08', date '2030-01-19', 60, 240);
  perform pg_temp.ladder_row(w, l8, r, 'economy', 80, 'jump', date '2029-12-08', 300, -20);
  perform pg_temp.ladder_row(w, l8, r, 'economy', 80, 'hold', date '2029-12-22', 240, 0);
  r := pg_temp.ladder_route(w, l8, 'ZV0', 'ZV7', 97, 0, 0, date '2029-11-01', ty, cy, with_base => false);
  perform pg_temp.ul_days(w, l8, 'ZV0', 'ZV7', 97, date '2029-11-24', date '2029-12-08', 40, 300);
  perform pg_temp.ul_days(w, l8, 'ZV0', 'ZV7', 97, date '2029-12-08', date '2030-01-12', 60, 240);
  perform pg_temp.ul_days(w, l8, 'ZV0', 'ZV7', 97, date '2030-01-12', date '2030-01-19', 100, 240);
  perform pg_temp.ladder_row(w, l8, r, 'economy', 80, 'jump', date '2029-12-08', 300, -20);
  perform pg_temp.ladder_row(w, l8, r, 'economy', 80, 'hold', date '2029-12-22', 240, 0);
  -- ZV8: jumped on 5 Jan, didn't pay
  r := pg_temp.ladder_route(w, l8, 'ZV0', 'ZV8', 98, 0, 0, date '2029-11-01', ty, cy, with_base => false);
  perform pg_temp.ul_days(w, l8, 'ZV0', 'ZV8', 98, date '2029-12-22', date '2030-01-05', 40, 300);
  perform pg_temp.ul_days(w, l8, 'ZV0', 'ZV8', 98, date '2030-01-05', date '2030-01-19', 40, 240);
  perform pg_temp.ladder_row(w, l8, r, 'economy', 80, 'jump', date '2030-01-05', 300, -20);
  -- ZV9 and ZVA: to 80 on 22 Dec, to 60 on 5 Jan
  r := pg_temp.ladder_route(w, l8, 'ZV0', 'ZV9', 99, 0, 0, date '2029-11-01', ty, cy, with_base => false);
  perform pg_temp.ul_days(w, l8, 'ZV0', 'ZV9', 99, date '2029-12-08', date '2029-12-22', 40, 300);
  perform pg_temp.ul_days(w, l8, 'ZV0', 'ZV9', 99, date '2029-12-22', date '2030-01-05', 40, 240);
  perform pg_temp.ul_days(w, l8, 'ZV0', 'ZV9', 99, date '2030-01-05', date '2030-01-19', 38, 180);
  perform pg_temp.ladder_row(w, l8, r, 'economy', 80, 'jump', date '2029-12-22', 300, -20);
  perform pg_temp.ladder_row(w, l8, r, 'economy', 60, 'jump', date '2030-01-05', 240, -25);
  r := pg_temp.ladder_route(w, l8, 'ZV0', 'ZVA', 100, 0, 0, date '2029-11-01', ty, cy, with_base => false);
  perform pg_temp.ul_days(w, l8, 'ZV0', 'ZVA', 100, date '2029-12-08', date '2029-12-22', 25, 300);
  perform pg_temp.ul_days(w, l8, 'ZV0', 'ZVA', 100, date '2029-12-22', date '2030-01-05', 30, 240);
  perform pg_temp.ul_days(w, l8, 'ZV0', 'ZVA', 100, date '2030-01-05', date '2030-01-19', 50, 180);
  perform pg_temp.ladder_row(w, l8, r, 'economy', 80, 'jump', date '2029-12-22', 300, -20);
  perform pg_temp.ladder_row(w, l8, r, 'economy', 60, 'jump', date '2030-01-05', 240, -25);
  -- ZVB: at 105 since 22 Dec, 50% full
  r := pg_temp.ladder_route(w, l8, 'ZV0', 'ZVB', 101, 0, 0, date '2029-11-01', ty, cy, with_base => false);
  perform pg_temp.ul_days(w, l8, 'ZV0', 'ZVB', 101, date '2030-01-05', date '2030-01-19', 50, 315);
  perform pg_temp.ladder_row(w, l8, r, 'economy', 105, 'up', date '2029-12-22', 300, 5);
  -- L9 and L10: 41% full at launch (85%: 255)
  r := pg_temp.ladder_route(w, l9, 'ZY0', 'ZY1', 102, 0, 0, date '2029-11-01', ty, cy, with_base => false);
  perform pg_temp.ul_days(w, l9, 'ZY0', 'ZY1', 102, date '2030-01-05', date '2030-01-19', 41, 255);
  r := pg_temp.ladder_route(w, l10, 'ZX0', 'ZX1', 103, 0, 0, date '2029-11-01', ty, cy, with_base => false);
  perform pg_temp.ul_days(w, l10, 'ZX0', 'ZX1', 103, date '2030-01-05', date '2030-01-19', 41, 255);
  perform set_config('equinox.actor', '', true), set_config('equinox.actor_detail', '', true);
  insert into t_fl values ('l8', to_jsonb(l8)), ('l9', to_jsonb(l9)), ('l10', to_jsonb(l10));
end
$setup$;

-- the settings, and the fare plan's new moves
do $test$
declare tw bigint := (select (v #>> '{}')::bigint from t_fl where k = 'w');
  n_worlds int := (select count(*) from public.worlds where id <> tw); bad text; ry bigint;
begin
  -- every world but the test's own (which copied the settings without their dates)
  select string_agg(k.key, ', ') into bad
    from (values ('fare_under_launch_load_pct', '80'::jsonb), ('fare_under_launch_levels', '[80, 60]'::jsonb), ('fare_under_launch_days', '14'::jsonb),
                 ('fare_under_launch_min_flights', '10'::jsonb), ('fare_under_launch_decide_load_pct', '60'::jsonb)) k(key, v)
   where (select count(*) from public.settings s where s.key = k.key and s.airline_id is null and s.value = k.v and s.world_id <> tw
            and length(coalesce(s.description, '')) > 40 and s.unit is not null and s.since = date '2026-10-23' and s.reason is not null) <> n_worlds;
  assert bad is null, 'not in every world with its value, unit, description, date and reason: ' || bad;
  -- Ryanair's own levels, where the copy has Ryanair (airline 3)
  select a.id into ry from public.airlines a where a.id = 3 and a.planner_name = 'Ryanair';
  if ry is not null then
    assert (select s.value = '[75, 60]'::jsonb and s.description like '%Ryanair%' and s.since = date '2026-10-23'
              from public.settings s where s.airline_id = ry and s.key = 'fare_under_launch_levels'),
      'Ryanair has no fare_under_launch_levels row of its own, [75, 60], described';
    assert (select private.fig_fare_ladder(ry, now()) #> '{settings,under_launch,levels}') = '[75, 60]'::jsonb,
      'Ryanair''s fare ladder doesn''t read its own jump levels';
  end if;
  assert col_description('public.fare_plan'::regclass, (select attnum from pg_attribute where attrelid = 'public.fare_plan'::regclass and attname = 'ladder_move')) like '%jump%revert%',
    'fare_plan.ladder_move doesn''t describe jump and revert';
  insert into public.fare_plan (world_id, airline_id, status, ladder_move, legacy_key)
  select a.world_id, a.id, 'planned', m, 'ul-test-' || m from public.airlines a join public.worlds w on w.id = a.world_id and w.is_default
   cross join unnest(array['jump', 'revert']) m
   where a.id = (select min(id) from public.airlines a2 where a2.world_id = a.world_id);
  begin
    insert into public.fare_plan (world_id, airline_id, status, ladder_move)
    select a.world_id, a.id, 'planned', 'sideways' from public.airlines a join public.worlds w on w.id = a.world_id and w.is_default limit 1;
    assert false, 'fare_plan took a ladder move that isn''t up, down, hold, jump or revert';
  exception when check_violation then null;
  end;
  raise notice 'under launch: the five settings in each of the % world(s) (80%% full, levels [80, 60], 14 days, 10 flights, 60%% to decide), described; Ryanair''s own levels [75, 60]%; fare_plan.ladder_move takes jump and revert, described',
    n_worlds, case when ry is null then ' (no Ryanair on this copy)' else ', read by its fare ladder' end;
end
$test$;

-- L8, L9 and L10: each move under launch
do $test$
declare l8 bigint := (select (v #>> '{}')::bigint from t_fl where k = 'l8'); l9 bigint := (select (v #>> '{}')::bigint from t_fl where k = 'l9');
  l10 bigint := (select (v #>> '{}')::bigint from t_fl where k = 'l10'); l3 bigint := (select (v #>> '{}')::bigint from t_fl where k = 'l3');
  t timestamptz := (select (v #>> '{}')::timestamptz from t_fl where k = 't'); d jsonb; e jsonb; got text; want text;
begin
  d := private.fig_fare_ladder(l8, t);
  assert d #> '{settings,under_launch}' = '{"days": 14, "levels": [80, 60], "load_pct": 80, "min_flights": 10, "decide_load_pct": 60}'::jsonb,
    'the under-launch settings read aren''t the world''s: ' || (d #> '{settings,under_launch}')::text;
  select string_agg(x ->> 'dest' || ' ' || pg_temp.ladder_line(d, x ->> 'dest') || ' ' || (x ->> 'ladder_kind') || case when (x ->> 'decide')::boolean then ' decide' else '' end
                    || case when (x ->> 'to_plan')::boolean then ' to_plan' else '' end, '; ' order by x ->> 'dest') into got
    from jsonb_array_elements(d -> 'routes') x where x ->> 'direction' = 'out';
  want := 'ZV1 down 100>80 (41% full over 14 days at launch: to 80% for 2 weeks) jump to_plan; '
       || 'ZV2 hold 100>100 (sold out 0 of 7, at launch (100%)) hold; '
       || 'ZV3 out hold 100>100 (sold out 0 of 5, at launch (100%): 9 flights in 14 days, needs 10 to jump) / back hold 100>100 (no departures captured) hold; '
       || 'ZV4 hold 80>80 (at 80% since 12 Jan: judged on 26 Jan) hold; '
       || 'ZV5 hold 80>80 (at 80%: revenue a flight 25,920 against 21,600 at launch, paid off) hold to_plan; '
       || 'ZV6 hold 80>80 (under launch: climbs or holds only) hold; '
       || 'ZV7 up 80>85 (sold out 7 of 7) up to_plan; '
       || 'ZV8 down 80>60 (at 80%: revenue a flight 17,280 against 21,600 at launch: to 60% for 2 weeks) jump to_plan; '
       || 'ZV9 up 60>100 (at 60% for 2 weeks: 38% full, revenue a flight 12,240 against 21,600 at launch: back to launch; cut or keep? (Saturday review)) revert decide to_plan; '
       || 'ZVA hold 60>60 (at 60% for 2 weeks: 50% full, revenue a flight 16,200 against 13,500 at launch: holds at 60%; cut or keep? (Saturday review)) hold decide to_plan; '
       || 'ZVB down 105>100 (sold out 0 of 7, down to launch (100%)) down to_plan';
  assert got = want, 'L8''s moves under launch are ' || got;
  assert d -> 'moves' = '{"up": 4, "hold": 12, "down": 6, "jumps": 4, "decisions": 4}'::jsonb, 'L8''s moves (directions): ' || (d -> 'moves')::text;
  -- the states and figures, each direction's
  select string_agg(x ->> 'dest' || ' ' || coalesce(x #>> '{under_launch,state}', '—'), ', ' order by x ->> 'dest') into got
    from jsonb_array_elements(d -> 'routes') x where x ->> 'direction' = 'back';
  assert got = 'ZV1 launch, ZV2 launch, ZV3 launch, ZV4 holding, ZV5 due, ZV6 done, ZV7 done, ZV8 due, ZV9 due, ZVA due, ZVB —',
    'L8''s under-launch states are ' || got;
  select x -> 'under_launch' into e from jsonb_array_elements(d -> 'routes') x where x ->> 'dest' = 'ZV1' and x ->> 'direction' = 'out';
  assert e = '{"state": "launch", "window_load": 41.0, "window_flights": 14, "window_revenue": 22200.00}'::jsonb, 'ZV1 out''s under_launch is ' || e::text;
  select x -> 'under_launch' into e from jsonb_array_elements(d -> 'routes') x where x ->> 'dest' = 'ZV4' and x ->> 'direction' = 'back';
  assert e ->> 'jumped_on' = '2030-01-12' and e ->> 'judge_on' = '2030-01-26' and (e ->> 'window_flights')::int = 7, 'ZV4 back''s under_launch is ' || e::text;
  select x -> 'under_launch' into e from jsonb_array_elements(d -> 'routes') x where x ->> 'dest' = 'ZV9' and x ->> 'direction' = 'back';
  assert (e ->> 'baseline_revenue')::numeric = 21600 and (e ->> 'window_revenue')::numeric = 12240 and (e ->> 'window_load')::numeric = 38
     and (e ->> 'window_flights')::int = 14 and e ->> 'jumped_on' = '2030-01-05', 'ZV9 back''s under_launch is ' || e::text;
  -- the game actions: a jump to 80 is −20%, to 60 −40%, the revert +0%
  select string_agg(x ->> 'text', ' | ' order by (x ->> 'n')::int) into got from jsonb_array_elements(d -> 'actions') x where x ->> 'from' = 'ZV0';
  assert got = 'From ZV0 to ZV1: −20% of the default price, economy | From ZV0 to ZV7: −15% of the default price, economy | '
            || 'From ZV0 to ZV8: −40% of the default price, economy | From ZV0 to ZV9: +0% of the default price, economy | '
            || 'From ZV0 to ZVB: +0% of the default price, economy',
    'L8''s game actions are ' || got;
  assert (select x ->> 'sign' = '-' and x -> 'pct' = '20'::jsonb and x -> 'level' = '80'::jsonb from jsonb_array_elements(d -> 'actions') x where x ->> 'route' = 'ZV0–ZV1' limit 1),
    'ZV1''s jump isn''t a − 20 action at 80';

  -- Ryanair-like airlines: the world's levels give 80, its own row 75
  d := private.fig_fare_ladder(l9, t);
  assert pg_temp.ladder_line(d, 'ZY1') = 'down 85>80 (41% full over 14 days at launch: to 80% for 2 weeks)', 'ZY1: ' || coalesce(pg_temp.ladder_line(d, 'ZY1'), 'none');
  d := private.fig_fare_ladder(l10, t);
  assert pg_temp.ladder_line(d, 'ZX1') = 'down 85>75 (41% full over 14 days at launch: to 75% for 2 weeks)' and d #> '{settings,under_launch,levels}' = '[75, 60]'::jsonb,
    'ZX1, with Ryanair''s levels: ' || coalesce(pg_temp.ladder_line(d, 'ZX1'), 'none');
  assert (select x ->> 'text' from jsonb_array_elements(d -> 'actions') x where (x ->> 'n')::int = 1) = 'From ZX0 to ZX1: −25% of the default price, economy',
    'ZX1''s action isn''t −25%: ' || (d -> 'actions')::text;
  -- L3 (launch 55%): no level under its launch, so nothing under launch; its 60% floor as before (case 7)
  d := private.fig_fare_ladder(l3, t);
  assert not exists (select 1 from jsonb_array_elements(d -> 'routes') x where x ? 'under_launch' and x -> 'under_launch' <> 'null'::jsonb or (x ->> 'decide')::boolean)
     and (d #>> '{moves,jumps}')::int = 0, 'L3 has something under launch: ' || (d -> 'routes')::text;
  raise notice 'under launch: 41%% full for 14 days at launch jumps to 80 (−20%%); 85%% full or 9 flights doesn''t (waits, saying so); held 14 days from the day seen; paid at 80 stays (recorded), then only climbs or holds, or climbs to 85 when it sells out; not paid at 80 jumps to 60 (−40%%); not paid at 60 back to launch, decide; paid at 60 but 50%% full holds, decide; at 105 a 5-point step stops at launch; at 85%% launch the world''s levels give 80, Ryanair''s own 75 (−25%%); a launch of 55%% has none';
end
$test$;

-- a jump put on the fare plan this Saturday, and the fares userscript's list
do $test$
declare w bigint := (select (v #>> '{}')::bigint from t_fl where k = 'w'); l8 bigint := (select (v #>> '{}')::bigint from t_fl where k = 'l8');
  t timestamptz := (select (v #>> '{}')::timestamptz from t_fl where k = 't'); zv1 bigint := (select (v #>> '{}')::bigint from t_fl where k = 'zv1');
  d jsonb; e jsonb; id bigint; got text;
begin
  id := pg_temp.ladder_row(w, l8, zv1, 'economy', 80, 'jump', date '2030-01-19', 300, -20);
  d := private.fig_fare_ladder(l8, t);
  select x into e from jsonb_array_elements(d -> 'routes') x where x ->> 'dest' = 'ZV1' and x ->> 'direction' = 'back';
  assert (e ->> 'planned')::boolean and not (e ->> 'to_plan')::boolean and e ->> 'ladder_kind' = 'jump' and e ->> 'move' = 'down' and e ->> 'new_level' = '80',
    'ZV1''s jump on the fare plan isn''t planned, kind jump, down to 80: ' || e::text;
  assert (d #>> '{moves,jumps}')::int = 4, 'the planned jump isn''t counted, both ways: ' || (d -> 'moves')::text;
  select string_agg(x ->> 'text' || ' ' || (x -> 'plan_ids')::text, ' | ' order by (x ->> 'n')::int) into got
    from jsonb_array_elements(private.capture_fare_actions_doc(w, t) -> 'actions') x where x ->> 'route' = 'ZV0–ZV1';
  assert got = format('From ZV0 to ZV1: −20%% of the default price, economy [%s] | From ZV1 to ZV0: −20%% of the default price, economy [%s]', id, id),
    'capture_fare_actions() doesn''t list ZV1''s jump with its plan row: ' || coalesce(got, 'none');
  raise notice 'a jump on the fare plan this Saturday stays a jump (down to 80, counted), and capture_fare_actions() lists it both ways at −20%% with its plan row';
end
$test$;

-- ---------------------------------------------------------------- 13. per direction (spec docs/specs/2026-10-26-fare-ladder-per-direction.md §5)
-- Migration 20261026220000_fare_ladder_per_direction.sql. In the same world, at the same moment T, one more of our
-- airlines, LP (launch 100%; hub ZP0), every route flown since 1 Dec 2029 unless said, 7 departures each way in the week,
-- economy at 300 a level point of 100 (its first fares 300 both ways, so the fare index reads the level):
--   ZP1 at 105 (a both-directions row of 5 Jan): out sold out 7 of 7, back 80% full: out up to 110, back down to 100;
--   ZP2 sold out both ways, only 3 departures back: out up, back holds ("3 departures captured, needs 5");
--   ZP3 at 110 from a both-directions row of 5 Jan: both directions read it (up to 115);
--   ZP4 a both-directions row at 105 on 29 Dec, an out row at 110 on 5 Jan: out at 110 (its own, later), back at 105;
--   ZP5 an out row at 110 on 29 Dec, a both-directions row at 105 on 5 Jan: both at 105 (the later row wins);
--   ZP6 at 110 (both, 29 Dec), out stepped down to 105 on 12 Jan: out held after its step down, back climbs to 115;
--   ZP7 at launch, out 41% full for 14 days, back sold out: out jumps to 80, back climbs to 105;
--   ZP8 at launch, its fares back at 330 (110%): back set back to 100 first, out not;
--   ZP9 a rotation launched 16 Jan, out sold out, back 80%: both hold (a flight added);
--   ZPA a rival starting on the pair on 16 Jan, out sold out, back 80%: both paused;
--   ZPB business seats: out both cabins sold out (one action, both classes), back business sold out and economy 80%
--     (business alone).
-- Then fare_plan_status() sees ZP4's out row by its own direction's fares, and capture_fare_actions() lists an out row
-- put on the fare plan this Saturday From ZP0 to ZP1 only.

-- a direction's flights, one a day from d0 to d1 (not included), at `load`% full in economy and `fare`, departing at `hr`
create function pg_temp.dir_days(w bigint, al bigint, o text, d text, fno int, reg text, d0 date, d1 date, load numeric, fare numeric, hr int)
returns void language sql as $f$
  insert into public.game_flights (world_id, airline_id, game_date, flight_no, origin_code, dest_code, dep_local, dep_at, registration,
                                   eco_pax, eco_seats, eco_pct, eco_fare, loads_captured_at)
  select w, al, x::date, fno, o, d, lpad(hr::text, 2, '0') || ':00', x::date::timestamp at time zone 'UTC' + make_interval(hours => hr), reg,
         round(180 * load / 100), 180, load, fare, timestamptz '2030-01-19 11:00:00+00'
    from generate_series(d0, d1 - 1, interval '1 day') x
$f$;

do $setup$
declare w bigint := (select (v #>> '{}')::bigint from t_fl where k = 'w');
  g bigint; ty bigint; cy bigint; cj bigint; lp bigint; r bigint; x record;
begin
  perform set_config('equinox.actor', 'claude', true), set_config('equinox.actor_detail', 'fare ladder per direction test', true);
  select x2.id into g from public.groups x2 where x2.world_id = w and x2.kind = 'ours';
  select x2.id into ty from public.aircraft_types x2 where x2.world_id = w and x2.name = 'LADDER TEST TYPE';
  select x2.id into cy from public.cabin_configs x2 where x2.world_id = w and x2.code = 'LAD-Y';
  select x2.id into cj from public.cabin_configs x2 where x2.world_id = w and x2.code = 'LAD-J';
  insert into public.airports (code, utc_offset)
  select c, 0 from unnest(array['ZP0', 'ZP1', 'ZP2', 'ZP3', 'ZP4', 'ZP5', 'ZP6', 'ZP7', 'ZP8', 'ZP9', 'ZPA', 'ZPB']) c
  on conflict (code) do update set utc_offset = excluded.utc_offset;
  insert into public.airlines (world_id, group_id, game_id, planner_name, public_name, iata_code, home_airport_code, active, position)
  values (w, g, 990311, 'Ladder Per', 'L Per', 'LP', 'ZP0', true, 11) returning id into lp;
  insert into public.airline_bases (world_id, airline_id, airport_code, role, is_main, position) values (w, lp, 'ZP0', 'hub', true, 1);

  -- ZP1: at 105, out sold out, back 80%
  r := pg_temp.ladder_route(w, lp, 'ZP0', 'ZP1', 111, 14, 0, date '2029-12-01', ty, cy, 315);
  update public.game_flights set eco_pct = 100, eco_pax = 180 where airline_id = lp and registration = 'ZL-111' and origin_code = 'ZP0' and game_date >= '2030-01-12';
  perform pg_temp.ladder_row(w, lp, r, 'economy', 105, 'up', date '2030-01-05', 300, 5);
  insert into t_fl values ('zp1', to_jsonb(r));
  -- ZP2: 3 departures back
  r := pg_temp.ladder_route(w, lp, 'ZP0', 'ZP2', 112, 14, 14, date '2029-12-01', ty, cy);
  delete from public.game_flights where airline_id = lp and registration = 'ZL-112' and origin_code = 'ZP2' and game_date >= '2030-01-15';
  -- ZP3: a both-directions row
  r := pg_temp.ladder_route(w, lp, 'ZP0', 'ZP3', 113, 14, 14, date '2029-12-01', ty, cy, 330);
  perform pg_temp.ladder_row(w, lp, r, 'economy', 110, 'up', date '2030-01-05', 300, 10);
  -- ZP4: an out row after a both-directions row; its fares out 330, back 315
  r := pg_temp.ladder_route(w, lp, 'ZP0', 'ZP4', 114, 14, 14, date '2029-12-01', ty, cy, 330);
  update public.game_flights set eco_fare = 315 where airline_id = lp and registration = 'ZL-114' and origin_code = 'ZP4' and game_date >= '2030-01-12';
  perform pg_temp.ladder_row(w, lp, r, 'economy', 105, 'up', date '2029-12-29', 300, 5);
  insert into t_fl values ('zp4_out', to_jsonb(pg_temp.ladder_row(w, lp, r, 'economy', 110, 'up', date '2030-01-05', 315, 4.8, 'out')));
  -- ZP5: a both-directions row after an out row
  r := pg_temp.ladder_route(w, lp, 'ZP0', 'ZP5', 115, 14, 14, date '2029-12-01', ty, cy, 315);
  perform pg_temp.ladder_row(w, lp, r, 'economy', 110, 'up', date '2029-12-29', 300, 10, 'out');
  perform pg_temp.ladder_row(w, lp, r, 'economy', 105, 'up', date '2030-01-05', 330, -4.5);
  -- ZP6: out stepped down on 12 Jan; its fares out 315, back 330
  r := pg_temp.ladder_route(w, lp, 'ZP0', 'ZP6', 116, 14, 14, date '2029-12-01', ty, cy, 330);
  update public.game_flights set eco_fare = 315 where airline_id = lp and registration = 'ZL-116' and origin_code = 'ZP0' and game_date >= '2030-01-12';
  perform pg_temp.ladder_row(w, lp, r, 'economy', 110, 'up', date '2029-12-29', 300, 10);
  perform pg_temp.ladder_row(w, lp, r, 'economy', 105, 'down', date '2030-01-12', 330, -4.5, 'out');
  -- ZP7: under launch out only (14 days at 41% full out, sold out back), launched 1 Nov
  r := pg_temp.ladder_route(w, lp, 'ZP0', 'ZP7', 117, 0, 0, date '2029-11-01', ty, cy, with_base => false);
  perform pg_temp.dir_days(w, lp, 'ZP0', 'ZP7', 5234, 'ZL-117', date '2030-01-05', date '2030-01-19', 41, 300, 14);
  perform pg_temp.dir_days(w, lp, 'ZP7', 'ZP0', 5235, 'ZL-117', date '2030-01-05', date '2030-01-19', 100, 300, 18);
  -- ZP8: its fares back at 110%
  r := pg_temp.ladder_route(w, lp, 'ZP0', 'ZP8', 118, 14, 14, date '2029-12-01', ty, cy);
  update public.game_flights set eco_fare = 330 where airline_id = lp and registration = 'ZL-118' and origin_code = 'ZP8' and game_date >= '2030-01-12';
  -- ZP9: a rotation launched 16 Jan; ZPA: a rival from 16 Jan; out sold out, back 80%
  for x in select * from (values ('ZP9', 119), ('ZPA', 120)) v(dest, k) loop
    r := pg_temp.ladder_route(w, lp, 'ZP0', x.dest, x.k, 14, 0, date '2029-12-01', ty, cy);
    update public.game_flights set eco_pct = 100, eco_pax = 180 where airline_id = lp and registration = 'ZL-' || x.k and origin_code = 'ZP0' and game_date >= '2030-01-12';
    if x.dest = 'ZP9' then insert into public.rotations (world_id, airline_id, route_id, launched_on) values (w, lp, r, date '2030-01-16'); end if;
  end loop;
  update public.game_scan_schedules s set flights = s.flights || '[["QQ", 9, "ZP0", "ZPA", "1234567", "08:00", "09:00", "A320", ""]]'::jsonb
    from public.game_scans sc, public.airlines a
   where sc.id = s.scan_id and sc.world_id = w and sc.taken_at >= timestamptz '2030-01-16 00:00:00+00'
     and a.id = s.airline_id and a.game_name = 'Quest Air' and a.world_id = w;
  -- ZPB: business seats; out both cabins sold out, back business sold out and economy 80%
  r := pg_temp.ladder_route(w, lp, 'ZP0', 'ZPB', 121, 14, 0, date '2029-12-01', ty, cj, 300, 14);
  update public.game_flights set eco_pct = 100, eco_pax = 180 where airline_id = lp and registration = 'ZL-121' and origin_code = 'ZP0' and game_date >= '2030-01-12';
  perform set_config('equinox.actor', '', true), set_config('equinox.actor_detail', '', true);
  insert into t_fl values ('lp', to_jsonb(lp));
end
$setup$;

do $test$
declare lp bigint := (select (v #>> '{}')::bigint from t_fl where k = 'lp'); t timestamptz := (select (v #>> '{}')::timestamptz from t_fl where k = 't');
  d jsonb; e jsonb; got text;
begin
  d := private.fig_fare_ladder(lp, t);
  -- one direction sold out and the other at 80%: out up, back down, each with its own load
  assert pg_temp.ladder_dirs(d, 'ZP1') = 'out economy up 105>110 (sold out 7 of 7); back economy down 105>100 (sold out 0 of 7, down to launch (100%))',
    'ZP1, out sold out and back 80% full: ' || pg_temp.ladder_dirs(d, 'ZP1');
  assert (select string_agg(x ->> 'direction' || ' ' || (x ->> 'from') || '>' || (x ->> 'to') || ' ' || (x ->> 'load') || ' ' || (x ->> 'sold_out_share'), ', ' order by o)
            from jsonb_array_elements(d -> 'routes') with ordinality t(x, o) where x ->> 'dest' = 'ZP1') = 'out ZP0>ZP1 100.0 100.0, back ZP1>ZP0 80.0 0.0',
    'ZP1''s rows aren''t from and to its airports with their own load and share: ' || (select string_agg(x::text, ' ') from jsonb_array_elements(d -> 'routes') x where x ->> 'dest' = 'ZP1');
  -- one direction under the minimum departures
  assert pg_temp.ladder_dirs(d, 'ZP2') = 'out economy up 100>105 (sold out 7 of 7); back economy hold 100>100 (3 departures captured, needs 5)',
    'ZP2, 3 departures back: ' || pg_temp.ladder_dirs(d, 'ZP2');
  -- a both-directions row read by both; a direction's own row winning over an older both-directions row, and losing to a
  -- newer one
  assert pg_temp.ladder_dirs(d, 'ZP3') = 'out economy up 110>115 (sold out 7 of 7); back economy up 110>115 (sold out 7 of 7)',
    'ZP3, a both-directions row at 110: ' || pg_temp.ladder_dirs(d, 'ZP3');
  assert pg_temp.ladder_dirs(d, 'ZP4') = 'out economy up 110>115 (sold out 7 of 7); back economy up 105>110 (sold out 7 of 7)',
    'ZP4, its out row (110, 5 Jan) after a both-directions row (105, 29 Dec): ' || pg_temp.ladder_dirs(d, 'ZP4');
  assert pg_temp.ladder_dirs(d, 'ZP5') = 'out economy up 105>110 (sold out 7 of 7); back economy up 105>110 (sold out 7 of 7)',
    'ZP5, a both-directions row (105, 5 Jan) after its out row (110, 29 Dec): ' || pg_temp.ladder_dirs(d, 'ZP5');
  assert (select bool_and((x ->> 'recorded')::boolean and (x ->> 'index_matches')::boolean) from jsonb_array_elements(d -> 'routes') x where x ->> 'dest' in ('ZP3', 'ZP4', 'ZP5')),
    'ZP3 to ZP5 aren''t recorded levels their fares match: ' || (d -> 'routes')::text;
  -- the hold after a step down on one direction only
  assert pg_temp.ladder_dirs(d, 'ZP6') = 'out economy hold 105>105 (held after a step down on 12 Jan); back economy up 110>115 (sold out 7 of 7)',
    'ZP6, out stepped down on 12 Jan: ' || pg_temp.ladder_dirs(d, 'ZP6');
  -- under launch on one direction only, its window that direction's flights
  assert pg_temp.ladder_dirs(d, 'ZP7') = 'out economy down 100>80 (41% full over 14 days at launch: to 80% for 2 weeks); back economy up 100>105 (sold out 7 of 7)',
    'ZP7, out 41% full at launch and back sold out: ' || pg_temp.ladder_dirs(d, 'ZP7');
  select x into e from jsonb_array_elements(d -> 'routes') x where x ->> 'dest' = 'ZP7' and x ->> 'direction' = 'out';
  assert e ->> 'ladder_kind' = 'jump' and e -> 'under_launch' = '{"state": "launch", "window_load": 41.0, "window_flights": 14, "window_revenue": 22200.00}'::jsonb,
    'ZP7 out''s jump isn''t judged on its own 14 flights: ' || e::text;
  select x into e from jsonb_array_elements(d -> 'routes') x where x ->> 'dest' = 'ZP7' and x ->> 'direction' = 'back';
  assert e ->> 'ladder_kind' = 'up' and (e #>> '{under_launch,window_load}')::numeric = 100, 'ZP7 back isn''t up on its own load: ' || e::text;
  -- a set-back on one direction only
  assert (select string_agg(x ->> 'direction' || ' ' || (x ->> 'fix') || ' ' || coalesce(x ->> 'fix_reason', '—'), ', ' order by o)
            from jsonb_array_elements(d -> 'routes') with ordinality t(x, o) where x ->> 'dest' = 'ZP8') = 'out false —, back true captured fare at 110%, level 100%',
    'ZP8 isn''t set back on its back direction only: ' || (select string_agg(x::text, ' ') from jsonb_array_elements(d -> 'routes') x where x ->> 'dest' = 'ZP8');
  -- the capacity hold and the rival pause hold both directions, one of them sold out
  assert pg_temp.ladder_line(d, 'ZP9') = 'hold 100>100 (a flight added on 16 Jan: judged at its new size from 23 Jan)', 'ZP9, a flight added: ' || pg_temp.ladder_dirs(d, 'ZP9');
  assert pg_temp.ladder_line(d, 'ZPA') = 'hold 100>100 (rival Quest Air started here on 16 Jan: paused until 23 Jan)', 'ZPA, a rival started: ' || pg_temp.ladder_dirs(d, 'ZPA');
  assert (select count(*) from jsonb_array_elements(d -> 'routes') x where x ->> 'dest' in ('ZP9', 'ZPA') and not (x ->> 'to_plan')::boolean) = 4,
    'a direction of a held or paused route would go on the fare plan';
  -- business seats: out both cabins up, back business up and economy at launch
  assert pg_temp.ladder_dirs(d, 'ZPB') = 'out economy up 100>105 (sold out 7 of 7); out business up 100>105 (sold out 7 of 7); '
                                      || 'back economy hold 100>100 (sold out 0 of 7, at launch (100%)); back business up 100>105 (sold out 7 of 7)',
    'ZPB: ' || pg_temp.ladder_dirs(d, 'ZPB');
  -- the actions: one per direction, the set-back first, both classes ticked when a direction's cabins agree; none for a
  -- direction that holds
  select string_agg(x ->> 'n' || '. ' || (x ->> 'text') || case when (x ->> 'fix')::boolean then ' [fix]' else '' end, ' | ' order by (x ->> 'n')::int) into got
    from jsonb_array_elements(d -> 'actions') x;
  assert got = '1. From ZP8 to ZP0: +0% of the default price, economy [fix] | '
            || '2. From ZP0 to ZP1: +10% of the default price, economy | 3. From ZP1 to ZP0: +0% of the default price, economy | '
            || '4. From ZP0 to ZP2: +5% of the default price, economy | '
            || '5. From ZP0 to ZP3: +15% of the default price, economy | 6. From ZP3 to ZP0: +15% of the default price, economy | '
            || '7. From ZP0 to ZP4: +15% of the default price, economy | 8. From ZP4 to ZP0: +10% of the default price, economy | '
            || '9. From ZP0 to ZP5: +10% of the default price, economy | 10. From ZP5 to ZP0: +10% of the default price, economy | '
            || '11. From ZP6 to ZP0: +15% of the default price, economy | '
            || '12. From ZP0 to ZP7: −20% of the default price, economy | 13. From ZP7 to ZP0: +5% of the default price, economy | '
            || '14. From ZP0 to ZP8: +5% of the default price, economy | 15. From ZP8 to ZP0: +5% of the default price, economy | '
            || '16. From ZP0 to ZPB: +5% of the default price, economy and business | 17. From ZPB to ZP0: +5% of the default price, business',
    'LP''s game actions are ' || got;
  assert (select x ->> 'route' = 'ZP0–ZP8' and x ->> 'from' = 'ZP8' and x ->> 'to' = 'ZP0' and x ->> 'reason' = 'captured fare at 110%, level 100%'
            from jsonb_array_elements(d -> 'actions') x where (x ->> 'n')::int = 1) and (d ->> 'off_level')::int = 1,
    'ZP8''s set-back isn''t the route ZP0–ZP8 from ZP8 to ZP0 with its reason, or off_level isn''t 1 direction: ' || (d -> 'actions' -> 0)::text;
  raise notice 'per direction: out sold out and back at 80%% go up and down apart, each with its own load; a direction under 5 departures holds; a both-directions row counts for both until a direction''s own later row, and a later both-directions row wins over an older own row; the hold after a step down, under launch''s jump and a set-back on one direction only; a new frequency and a rival hold both; 17 actions, one per direction, the set-back first, both classes in one where a direction''s cabins agree';
end
$test$;

-- fare_plan_status() reads a direction's row on its own direction's fares; capture_fare_actions() matches a direction
do $test$
declare w bigint := (select (v #>> '{}')::bigint from t_fl where k = 'w'); lp bigint := (select (v #>> '{}')::bigint from t_fl where k = 'lp');
  t timestamptz := (select (v #>> '{}')::timestamptz from t_fl where k = 't'); zp1 bigint := (select (v #>> '{}')::bigint from t_fl where k = 'zp1');
  zp4 bigint := (select (v #>> '{}')::bigint from t_fl where k = 'zp4_out'); p jsonb; d jsonb; id bigint; got text;
begin
  -- ZP4 out: 315 → 330 (+4.8%) on its out flights from 12 Jan; both directions together (322.50) wouldn't show it
  select x into p from jsonb_array_elements(private.fig_fare_plan(lp, t) -> 'plan') x where (x ->> 'id')::bigint = zp4;
  assert (p ->> 'applied')::boolean and p ->> 'seen_on' = '2030-01-12' and p ->> 'direction' = 'out' and (p ->> 'fare_now')::numeric = 330,
    'ZP4''s out row isn''t seen on 12 Jan on its out fares: ' || p::text;
  assert (select bool_and(x ? 'direction') and count(*) filter (where x ->> 'direction' = 'out') = 3 and count(*) filter (where x ->> 'direction' is null) = 5
            from jsonb_array_elements(private.fig_fare_plan(lp, t) -> 'plan') x),
    'fare_plan_status() doesn''t give each row its direction (3 out, 5 both): ' || (private.fig_fare_plan(lp, t) -> 'plan')::text;
  -- an out row put on the fare plan this Saturday: ZP1 out planned, its back not; the userscript's list has From ZP0 to ZP1
  -- with its plan row (unseen), not From ZP1 to ZP0, and ZP8's set-back
  id := pg_temp.ladder_row(w, lp, zp1, 'economy', 110, 'up', date '2030-01-19', 315, 4.8, 'out');
  d := private.fig_fare_ladder(lp, t);
  assert (select string_agg(x ->> 'direction' || ' ' || (x ->> 'planned') || ' ' || coalesce(x ->> 'plan_id', '—') || ' ' || (x ->> 'to_plan'), ', ' order by o)
            from jsonb_array_elements(d -> 'routes') with ordinality t(x, o) where (x ->> 'route_id')::bigint = zp1) = format('out true %s false, back false — true', id),
    'ZP1''s out row this Saturday isn''t on its out direction only: ' || (select string_agg(x::text, ' ') from jsonb_array_elements(d -> 'routes') x where (x ->> 'route_id')::bigint = zp1);
  select string_agg(x ->> 'text' || ' ' || (x -> 'plan_ids')::text, ' | ' order by (x ->> 'n')::int) into got
    from jsonb_array_elements(private.capture_fare_actions_doc(w, t) -> 'actions') x where (x ->> 'game_id')::int = 990311;
  assert got = format('From ZP8 to ZP0: +0%% of the default price, economy [] | From ZP0 to ZP1: +10%% of the default price, economy [%s]', id),
    'capture_fare_actions() doesn''t list ZP1''s out row alone (and ZP8''s set-back): ' || coalesce(got, 'none');
  raise notice 'fare_plan_status() sees an out row on its out fares (12 Jan; both directions together wouldn''t) and gives each row its direction; an out row on the fare plan this Saturday is planned out only, and capture_fare_actions() lists From ZP0 to ZP1 with its plan row, not the way back';
end
$test$;

-- ---------------------------------------------------------------- 14. the hold after a step up (spec docs/specs/2026-10-26-fare-ladder-hold-after-step-up.md)
-- Migration 20261027000000_fare_ladder_up_hold.sql. In the same world, at the same moment T (Saturday 19 Jan 2030), one
-- more of our airlines, LH (launch 100%; hub ZH0), every route flown since 1 Dec 2029, sold out 7 of 7 each way in the
-- week (so every direction not held goes up), economy only, its fares at each direction's level (no set-backs):
--   ZH1 a both-directions step up to 105 on 14 Jan (5 days before T): both directions held, "held after a step up on
--       14 Jan", no move, no action, nothing to put on the fare plan; with fare_ladder_up_hold_weeks at 0, both go up;
--   ZH2 an out step up to 105 on 12 Jan (7 days): judged as normal, out up to 110; back (no row) up to 105;
--   ZH3 both up to 110 on 29 Dec, out down to 105 on 12 Jan: out keeps the 2-week hold after a step down and its reason;
--       back up to 115;
--   ZH4 both up to 105 on 29 Dec, a revert to 100 on 14 Jan: not held, up to 105 both ways;
--   ZH5 a hold row at 100 on 14 Jan: not held, up to 105 both ways;
--   ZH6 both up to 110 on 29 Dec, out down to 105 on 7 Jan (12 days: still held after it), out up to 110 on 14 Jan: out
--       held both ways, the more recent move (the step up) gives the reason; back up to 115.
-- (A set-back writes no fare plan row, and ladder_move takes no other value, so nothing else could start the hold.)
do $setup$
declare w bigint := (select (v #>> '{}')::bigint from t_fl where k = 'w');
  g bigint; ty bigint; cy bigint; lh bigint; r bigint;
begin
  perform set_config('equinox.actor', 'claude', true), set_config('equinox.actor_detail', 'fare ladder hold after a step up test', true);
  select x2.id into g from public.groups x2 where x2.world_id = w and x2.kind = 'ours';
  select x2.id into ty from public.aircraft_types x2 where x2.world_id = w and x2.name = 'LADDER TEST TYPE';
  select x2.id into cy from public.cabin_configs x2 where x2.world_id = w and x2.code = 'LAD-Y';
  insert into public.airports (code, utc_offset)
  select c, 0 from unnest(array['ZH0', 'ZH1', 'ZH2', 'ZH3', 'ZH4', 'ZH5', 'ZH6']) c
  on conflict (code) do update set utc_offset = excluded.utc_offset;
  insert into public.airlines (world_id, group_id, game_id, planner_name, public_name, iata_code, home_airport_code, active, position)
  values (w, g, 990312, 'Ladder Hold', 'L Hold', 'LH', 'ZH0', true, 12) returning id into lh;
  insert into public.airline_bases (world_id, airline_id, airport_code, role, is_main, position) values (w, lh, 'ZH0', 'hub', true, 1);
  -- ZH1: a both-directions step up 5 days before T
  r := pg_temp.ladder_route(w, lh, 'ZH0', 'ZH1', 131, 14, 14, date '2029-12-01', ty, cy, 315);
  perform pg_temp.ladder_row(w, lh, r, 'economy', 105, 'up', date '2030-01-14', 300, 5);
  -- ZH2: an out step up 7 days before T; out fares 315, back 300
  r := pg_temp.ladder_route(w, lh, 'ZH0', 'ZH2', 132, 14, 14, date '2029-12-01', ty, cy, 300);
  update public.game_flights set eco_fare = 315 where airline_id = lh and registration = 'ZL-132' and origin_code = 'ZH0' and game_date >= '2030-01-12';
  perform pg_temp.ladder_row(w, lh, r, 'economy', 105, 'up', date '2030-01-12', 300, 5, 'out');
  -- ZH3: out stepped down on 12 Jan; out fares 315, back 330
  r := pg_temp.ladder_route(w, lh, 'ZH0', 'ZH3', 133, 14, 14, date '2029-12-01', ty, cy, 330);
  update public.game_flights set eco_fare = 315 where airline_id = lh and registration = 'ZL-133' and origin_code = 'ZH0' and game_date >= '2030-01-12';
  perform pg_temp.ladder_row(w, lh, r, 'economy', 110, 'up', date '2029-12-29', 300, 10);
  perform pg_temp.ladder_row(w, lh, r, 'economy', 105, 'down', date '2030-01-12', 330, -4.5, 'out');
  -- ZH4: a revert on 14 Jan
  r := pg_temp.ladder_route(w, lh, 'ZH0', 'ZH4', 134, 14, 14, date '2029-12-01', ty, cy, 300);
  perform pg_temp.ladder_row(w, lh, r, 'economy', 105, 'up', date '2029-12-29', 300, 5);
  perform pg_temp.ladder_row(w, lh, r, 'economy', 100, 'revert', date '2030-01-14', 315, -4.8);
  -- ZH5: a hold row on 14 Jan
  r := pg_temp.ladder_route(w, lh, 'ZH0', 'ZH5', 135, 14, 14, date '2029-12-01', ty, cy, 300);
  perform pg_temp.ladder_row(w, lh, r, 'economy', 100, 'hold', date '2030-01-14', 300, 0);
  -- ZH6: out down on 7 Jan, then up again on 14 Jan
  r := pg_temp.ladder_route(w, lh, 'ZH0', 'ZH6', 136, 14, 14, date '2029-12-01', ty, cy, 330);
  perform pg_temp.ladder_row(w, lh, r, 'economy', 110, 'up', date '2029-12-29', 300, 10);
  perform pg_temp.ladder_row(w, lh, r, 'economy', 105, 'down', date '2030-01-07', 330, -4.5, 'out');
  perform pg_temp.ladder_row(w, lh, r, 'economy', 110, 'up', date '2030-01-14', 315, 4.8, 'out');
  perform set_config('equinox.actor', '', true), set_config('equinox.actor_detail', '', true);
  insert into t_fl values ('lh', to_jsonb(lh));
end
$setup$;

do $test$
declare w bigint := (select (v #>> '{}')::bigint from t_fl where k = 'w'); lh bigint := (select (v #>> '{}')::bigint from t_fl where k = 'lh');
  t timestamptz := (select (v #>> '{}')::timestamptz from t_fl where k = 't'); d jsonb; got text;
begin
  -- the setting: 1 week, in every world, airline null, described, with its date and reason
  assert (select count(*) from public.settings s where s.key = 'fare_ladder_up_hold_weeks' and s.airline_id is null and s.value = '1'::jsonb
            and s.unit = 'weeks' and length(coalesce(s.description, '')) > 40 and s.since = date '2026-10-26' and s.reason is not null
            and s.world_id <> w) = (select count(*) from public.worlds where id <> w),
    'fare_ladder_up_hold_weeks isn''t in every world at 1 week with its unit, description, date and reason';
  d := private.fig_fare_ladder(lh, t);
  assert d #>> '{settings,up_hold_weeks}' = '1' and d #>> '{settings,hold_weeks}' = '2',
    'the settings echo doesn''t give up_hold_weeks 1 beside hold_weeks 2: ' || (d -> 'settings')::text;
  -- stepped up 5 days before the Saturday: held both ways (a both-directions row), no move, no action, not to the plan
  assert pg_temp.ladder_dirs(d, 'ZH1') = 'out economy hold 105>105 (held after a step up on 14 Jan); back economy hold 105>105 (held after a step up on 14 Jan)',
    'ZH1, stepped up on 14 Jan: ' || pg_temp.ladder_dirs(d, 'ZH1');
  assert (select bool_and(x ->> 'ladder_kind' = 'hold' and not (x ->> 'to_plan')::boolean and not (x ->> 'fix')::boolean and (x ->> 'index_matches')::boolean)
            from jsonb_array_elements(d -> 'routes') x where x ->> 'dest' = 'ZH1'),
    'ZH1''s held directions would go on the fare plan, be set back, or aren''t at their level: '
      || (select string_agg(x::text, ' ') from jsonb_array_elements(d -> 'routes') x where x ->> 'dest' = 'ZH1');
  -- 7 days: judged as normal
  assert pg_temp.ladder_dirs(d, 'ZH2') = 'out economy up 105>110 (sold out 7 of 7); back economy up 100>105 (sold out 7 of 7)',
    'ZH2, stepped up out on 12 Jan (7 days): ' || pg_temp.ladder_dirs(d, 'ZH2');
  -- the hold after a step down keeps its 2 weeks and its reason
  assert pg_temp.ladder_dirs(d, 'ZH3') = 'out economy hold 105>105 (held after a step down on 12 Jan); back economy up 110>115 (sold out 7 of 7)',
    'ZH3, stepped down out on 12 Jan: ' || pg_temp.ladder_dirs(d, 'ZH3');
  assert (select (x ->> 'to_plan')::boolean from jsonb_array_elements(d -> 'routes') x where x ->> 'dest' = 'ZH3' and x ->> 'direction' = 'out'),
    'ZH3 out''s hold after a step down no longer goes on the fare plan';
  -- a revert or a hold row doesn't start the hold
  assert pg_temp.ladder_dirs(d, 'ZH4') = 'out economy up 100>105 (sold out 7 of 7); back economy up 100>105 (sold out 7 of 7)',
    'ZH4, a revert on 14 Jan: ' || pg_temp.ladder_dirs(d, 'ZH4');
  assert pg_temp.ladder_dirs(d, 'ZH5') = 'out economy up 100>105 (sold out 7 of 7); back economy up 100>105 (sold out 7 of 7)',
    'ZH5, a hold row on 14 Jan: ' || pg_temp.ladder_dirs(d, 'ZH5');
  -- held both ways: the more recent move's reason
  assert pg_temp.ladder_dirs(d, 'ZH6') = 'out economy hold 110>110 (held after a step up on 14 Jan); back economy up 110>115 (sold out 7 of 7)',
    'ZH6, out down on 7 Jan and up on 14 Jan: ' || pg_temp.ladder_dirs(d, 'ZH6');
  -- the actions: none for a held direction
  select string_agg(x ->> 'n' || '. ' || (x ->> 'text') || case when (x ->> 'fix')::boolean then ' [fix]' else '' end, ' | ' order by (x ->> 'n')::int) into got
    from jsonb_array_elements(d -> 'actions') x;
  assert got = '1. From ZH0 to ZH2: +10% of the default price, economy | 2. From ZH2 to ZH0: +5% of the default price, economy | '
            || '3. From ZH3 to ZH0: +15% of the default price, economy | '
            || '4. From ZH0 to ZH4: +5% of the default price, economy | 5. From ZH4 to ZH0: +5% of the default price, economy | '
            || '6. From ZH0 to ZH5: +5% of the default price, economy | 7. From ZH5 to ZH0: +5% of the default price, economy | '
            || '8. From ZH6 to ZH0: +15% of the default price, economy',
    'LH''s game actions are ' || coalesce(got, 'none');
  -- the hold is the setting's: at 0 weeks ZH1 is judged as normal
  update public.settings set value = '0'::jsonb where world_id = w and airline_id is null and key = 'fare_ladder_up_hold_weeks';
  d := private.fig_fare_ladder(lh, t);
  assert pg_temp.ladder_dirs(d, 'ZH1') = 'out economy up 105>110 (sold out 7 of 7); back economy up 105>110 (sold out 7 of 7)',
    'ZH1 with fare_ladder_up_hold_weeks at 0: ' || pg_temp.ladder_dirs(d, 'ZH1');
  update public.settings set value = '1'::jsonb where world_id = w and airline_id is null and key = 'fare_ladder_up_hold_weeks';
  raise notice 'the hold after a step up: fare_ladder_up_hold_weeks 1 in every world, described, echoed as up_hold_weeks; stepped up 5 days before the Saturday holds ("held after a step up on 14 Jan"), both directions for a both-directions row, with no action and nothing to put on the fare plan; at 7 days it is judged; the hold after a step down keeps its 2 weeks and reason; a revert or a hold row doesn''t hold; held both ways, the more recent move''s reason; at 0 weeks nothing is held';
end
$test$;

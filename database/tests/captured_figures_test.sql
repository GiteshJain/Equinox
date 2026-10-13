-- The captured figures (decision #19, build pull request 3; spec docs/specs/2026-10-12-captured-figures.md §3), on
-- hand-made rows. Run by database/rehearse.sh on the copy of last night's backup, after the new migrations, inside a
-- transaction that is rolled back. A failed check stops with an error that says where (names and figures of the
-- hand-made rows only). Everything is made in a world of its own, so nothing on the copy is touched or counted:
--   airline One (home and main hub ZZ1, UTC+5:30, a focus city at ZZ2): one rotation ZZ1-ZZ2 flown daily both ways
--   (2 flights a day), 6 flights in its last 24 hours of bank statement (each 20k profit: 0.04M a day), cash 10M
--   captured at T = 2030-01-15 11:00 UTC (9M the day before, 4M captured and 5M typed on 1 Jan, and 50M captured after
--   the moment), a week-end closing (1M) and two leasing payments (0.25M, 0.2M) on its events page, three types it may
--   buy (TEST JET A never leased, TEST JET B leased, TEST JET C dear), an order and a loss and a cabin in its spending
--   log; airline Two with no capture at all; airline Three with a balance and only 3 flights in its statement; a rival
--   with a world scan. The moment is T + 1 hour.
--   1. Who may call them: signed in only, as owner with an empty search path, described; the builders are internal.
--   2. cash_forecast(): the cash and its time, flight profit a day, every payment and its weekly repeat beyond what the
--      game lists, the points, the lowest point at a payment's own moment and that payment; each type's price with the
--      cabin it gets, its lease (10% of its price never leased, the highest payment seen when leased) and its first safe
--      day and how many today; two orders together, each with its own lease from 7 days after it is ordered; one more
--      than is safe; no capture, fewer than 5 flights; p_as_of before a capture ignores it.
--   3. airline_profit() and airline_cards(): an order payment between two captures is added back to profit, a loss
--      stays in profit, a cabin counts as an order payment; a typed figure wins before the last 7 days; the 7-day
--      profit, an early read; next order and can order now; no capture and fewer than 5 flights say what's missing.
--   4. route_profit(), aircraft_profit(), fare_changes(): a route with no loads matched; the aircraft's lease a day.
--   5. hub_progress() and capture_status(): the main hub's departures and its plan cards, an exemption, a contested
--      focus city (by departures and by a route) from the latest scan by the moment; the capture board.
--   6. Signed out and an account that isn't staff are refused by every function; export_for_report('figures') with the
--      ingest secret answers every function for every airline, and refuses a wrong secret.

create temporary table t_cf (k text primary key, v jsonb) on commit drop;
grant select, insert, update on t_cf to authenticated, anon;
insert into public.planner_users (email) values ('captured-figures-staff@example.com') on conflict do nothing;

-- ---------------------------------------------------------------- 1. who may call them
do $test$
declare f text; n int := 0;
begin
  foreach f in array array['public.cash_forecast(bigint, jsonb, timestamptz)', 'public.airline_cards(bigint, timestamptz)',
                           'public.airline_profit(bigint, timestamptz)', 'public.route_profit(bigint, integer, timestamptz)',
                           'public.aircraft_profit(bigint, integer, timestamptz)', 'public.growth_signals(bigint, timestamptz)',
                           'public.hub_progress(bigint, timestamptz)', 'public.capture_status(bigint, timestamptz)',
                           'public.fare_changes(bigint, timestamptz)'] loop
    assert (select p.prosecdef and p.provolatile = 's' and coalesce('search_path=""' = any (p.proconfig), false) from pg_proc p where p.oid = f::regprocedure),
      f || ' isn''t stable, run as owner with an empty search path';
    assert not has_function_privilege('anon', f, 'execute'), 'signed out, ' || f || ' can be called';
    assert has_function_privilege('authenticated', f, 'execute'), 'signed in, ' || f || ' can''t be called';
    assert obj_description(f::regprocedure, 'pg_proc') is not null, f || ' has no description';
    n := n + 1;
  end loop;
  assert not exists (select 1 from pg_proc p join pg_namespace s on s.oid = p.pronamespace
                      cross join aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                      where (s.nspname = 'private' and p.proname like 'fig\_%') and (a.grantee = 0
                         or a.grantee in (select oid from pg_roles where rolname in ('anon', 'authenticated', 'service_role')))),
    'a builder of the captured figures (private.fig_*) can be called from outside the database';
  assert not exists (select 1 from pg_proc p join pg_namespace s on s.oid = p.pronamespace
                      where s.nspname = 'private' and p.proname like 'fig\_%'
                        and (obj_description(p.oid, 'pg_proc') is null or not coalesce('search_path=""' = any (p.proconfig), false))),
    'a builder of the captured figures has no description or no empty search path';
  assert obj_description('public.export_for_report(text, text, text)'::regprocedure, 'pg_proc') like '%kind figures%',
    'export_for_report()''s description doesn''t mention kind figures';
  raise notice 'who may call them: the % functions signed in only, stable, as owner with an empty search path, described; their % builders internal',
    n, (select count(*) from pg_proc p join pg_namespace s on s.oid = p.pronamespace where s.nspname = 'private' and p.proname like 'fig\_%');
end
$test$;

-- ---------------------------------------------------------------- the hand-made world
do $setup$
declare
  w bigint; g bigint; gr bigint; a1 bigint; a2 bigint; a3 bigint; rv bigint; ta bigint; tb bigint; tc bigint; ca bigint;
  r1 bigint; rot bigint; ac bigint; ac9 bigint; pc bigint; s1 bigint; s2 bigint;
  t timestamptz := '2030-01-15 11:00:00+00';
  dw bigint := (select id from public.worlds where is_default);
begin
  perform set_config('equinox.actor', 'claude', true), set_config('equinox.actor_detail', 'captured figures test', true);
  insert into public.airports (code, utc_offset) values ('ZZ1', 5.50), ('ZZ2', 0.00), ('ZZ3', 1.00)
  on conflict (code) do update set utc_offset = excluded.utc_offset;
  insert into public.worlds (name, game_host, kind) values ('captured figures test', 'captured-figures.test', 'exclusive') returning id into w;
  insert into public.settings (world_id, airline_id, key, value, unit, description)
  select w, null, s.key, s.value, s.unit, s.description from public.settings s where s.world_id = dw and s.airline_id is null;
  insert into public.groups (world_id, name, kind) values (w, 'ours', 'ours') returning id into g;
  insert into public.groups (world_id, name, kind) values (w, 'rival', 'rival') returning id into gr;
  insert into public.airlines (world_id, group_id, game_id, planner_name, public_name, iata_code, home_airport_code, active, position)
  values (w, g, 990001, 'Figures One', 'One', 'T1', 'ZZ1', true, 1) returning id into a1;
  insert into public.airlines (world_id, group_id, game_id, planner_name, public_name, iata_code, home_airport_code, active, position)
  values (w, g, 990002, 'Figures Two', 'Two', 'T2', 'ZZ1', true, 2) returning id into a2;
  insert into public.airlines (world_id, group_id, game_id, planner_name, public_name, iata_code, home_airport_code, active, position)
  values (w, g, 990003, 'Figures Three', 'Three', 'T3', 'ZZ1', true, 3) returning id into a3;
  insert into public.airlines (world_id, group_id, game_id, game_name) values (w, gr, 990009, 'Rival Air') returning id into rv;
  insert into public.settings (world_id, airline_id, key, value, description) values (w, a3, 'hub_first_exempt', 'true', 'test: Three is exempt');
  insert into public.airline_bases (world_id, airline_id, airport_code, role, is_main, position) values (w, a1, 'ZZ1', 'hub', true, 0);
  insert into public.airline_bases (world_id, airline_id, airport_code, role, is_main, position) values (w, a1, 'ZZ2', 'focus', false, 1);

  -- the types One may buy, their cabins (A: Leisure; B: Comfort, as it has no Leisure; C: none)
  insert into public.aircraft_types (world_id, name, price) values (w, 'TEST JET A', 2000000) returning id into ta;
  insert into public.aircraft_types (world_id, name, price) values (w, 'TEST JET B', 3000000) returning id into tb;
  insert into public.aircraft_types (world_id, name, price) values (w, 'TEST JET C', 7000000) returning id into tc;
  insert into public.cabin_configs (world_id, code, aircraft_type_id, cabin, cost) values (w, 'TA-LEI', ta, 'Leisure', 100000) returning id into ca;
  insert into public.cabin_configs (world_id, code, aircraft_type_id, cabin, cost) values (w, 'TB-CMF', tb, 'Comfort', 200000), (w, 'TB-LP', tb, 'Leisure Plus', 300000);
  insert into public.airline_aircraft_types (world_id, airline_id, aircraft_type_id) values (w, a1, ta), (w, a1, tb), (w, a1, tc);

  -- One's schedule: ZZ1-ZZ2 daily both ways on T1-001; T1-009 on order with a plan card from ZZ1
  insert into public.aircraft (world_id, airline_id, registration, aircraft_type_id, cabin_config_id, base_code, status)
  values (w, a1, 'T1-001', ta, ca, 'ZZ1', 'active') returning id into ac;
  insert into public.aircraft (world_id, airline_id, registration, aircraft_type_id, status, ordered_on) values (w, a1, 'T1-009', ta, 'on_order', '2030-01-14') returning id into ac9;
  insert into public.routes (world_id, airline_id, hub_code, dest_code, distance_km, source) values (w, a1, 'ZZ1', 'ZZ2', 1000, 'research') returning id into r1;
  insert into public.rotations (world_id, airline_id, route_id) values (w, a1, r1) returning id into rot;
  insert into public.flight_legs (world_id, airline_id, rotation_id, leg_no, flight_no, origin_code, dest_code, aircraft_id, days_utc, dep_utc_min, block_min)
  values (w, a1, rot, 1, 101, 'ZZ1', 'ZZ2', ac, '{1,2,3,4,5,6,7}', 360, 120), (w, a1, rot, 2, 102, 'ZZ2', 'ZZ1', ac, '{1,2,3,4,5,6,7}', 600, 120);
  insert into public.plan_cards (world_id, airline_id, aircraft_id, base_code, title) values (w, a1, ac9, 'ZZ1', 'test card') returning id into pc;
  insert into public.plan_card_legs (world_id, plan_card_id, position, flight_no, origin_code, dest_code, days_utc)
  values (w, pc, 1, 103, 'ZZ1', 'ZZ2', '{1,3,5}');
  insert into public.plan_card_legs (world_id, plan_card_id, position, flight_no, origin_code, dest_code) values (w, pc, 2, 105, 'ZZ1', 'ZZ2'), (w, pc, 3, 104, 'ZZ2', 'ZZ1');

  -- the capture: balances (account 2800), the bank statement's last 24 hours, the events page, the raw pages
  insert into public.game_balance (world_id, airline_id, airline, captured_on, capture_day, account, amount, captured_at) values
    (w, a1, 'Figures One', '2030-01-15', '2030-01-15', '2800 Bank account', 10000000, t),
    (w, a1, 'Figures One', '2030-01-14', '2030-01-14', '2800 Bank account', 9000000, t - interval '1 day'),
    (w, a1, 'Figures One', '2030-01-01', '2030-01-01', '2800 Bank account', 4000000, t - interval '14 days'),
    (w, a1, 'Figures One', '2030-01-16', '2030-01-15', '2800 Bank account', 50000000, t + interval '13 hours'),
    (w, a3, 'Figures Three', '2030-01-15', '2030-01-15', '2800 Bank account', 3000000, t);
  insert into public.cash_entries (world_id, airline_id, day, cash) values (w, a1, '2030-01-01', 5000000);
  insert into public.game_flights (world_id, airline_id, posted_at, statement_blk, statement_routes, origin_code, dest_code, maint_registration,
                                   pax_income, cargo_income, fuel, income_total, cost_total, money_captured_at)
  select w, a1, t - make_interval(hours => i), 1, 1, 'ZZ1', 'ZZ2', 'T1-001', 50000, 0, 30000, 50000, 30000, t from generate_series(1, 6) i;
  insert into public.game_flights (world_id, airline_id, posted_at, statement_blk, statement_routes, origin_code, dest_code,
                                   pax_income, cargo_income, fuel, income_total, cost_total, money_captured_at)
  select w, a3, t - make_interval(hours => i), 1, 1, 'ZZ1', 'ZZ2', 40000, 0, 30000, 40000, 30000, t from generate_series(1, 3) i;
  -- one loads row on the route, departing long after every block: no block is matched to it
  insert into public.game_flights (world_id, airline_id, game_date, flight_no, origin_code, dest_code, dep_local, registration, eco_pct, eco_fare, loads_captured_at)
  values (w, a1, '2030-01-15', 101, 'ZZ1', 'ZZ2', '23:50', 'T1-001', 100, 150, t);
  -- the events page, in local time at ZZ1 (UTC+5:30): 18 Jan 17:30 = T + 3d 1h, 20 Jan 17:30 = T + 5d 1h, 21 Jan 05:30 = T + 5d 13h
  insert into public.game_events (world_id, airline_id, airline, event_date, event_time, descr, debit, captured_at) values
    (w, a1, 'Figures One', '2030-01-18', '17:30', 'Week-end closing of Figures One', 1000000, t),
    (w, a1, 'Figures One', '2030-01-20', '17:30', 'Leasing payment for T1-001 (Test Jet B)', 250000, t),
    (w, a1, 'Figures One', '2030-01-21', '05:30', 'Leasing payment for T1-002 (Test Jet B)', 200000, t),
    (w, a1, 'Figures One', '2030-01-22', '05:30', 'Week-end closing of Figures One, captured after the moment', 9000000, t + interval '13 hours');
  insert into public.spending_log (world_id, airline_id, spent_on, amount, kind, note) values
    (w, a1, '2030-01-15', 2000000, 'order', 'test: an order between two captures'),
    (w, a1, '2030-01-15', 500000, 'loss', 'test: a loss stays in profit'),
    (w, a1, '2030-01-10', 100000, 'cabin', 'test: a cabin counts as an order payment');
  insert into public.game_capture_raw (world_id, airline_id, airline, kind, rows, captured_at)
  select w, a1, 'Figures One', k, '[]'::jsonb, t from unnest(array['loads', 'statement', 'events', 'pnl', 'balance']) k;
  insert into public.game_capture_raw (world_id, airline_id, airline, kind, rows, captured_at) values
    (w, a1, 'Figures One', 'loads', '[]'::jsonb, t - interval '1 day' + interval '5 minutes'),
    (w, a3, 'Figures Three', 'balance', '[]'::jsonb, t);

  -- a rival's world scans: at ZZ2 300 departures a week, and ZZ2-ZZ1 three times a day; the scan after the moment says otherwise
  insert into public.game_scans (taken_at, status, world_id) values (t - interval '1 day', 'done', w) returning id into s1;
  insert into public.game_scans (taken_at, status, world_id) values (t + interval '1 day', 'done', w) returning id into s2;
  insert into public.scan_airline_airports (scan_id, world_id, airline_id, airport_code, weekly_departures, destinations)
  values (s1, w, rv, 'ZZ2', 300, 2), (s2, w, rv, 'ZZ2', 10, 1);
  insert into public.game_scan_schedules (scan_id, world_id, airline_id, flights) values
    (s1, w, rv, '[["RV","1","ZZ2","ZZ1","1234567","07:00","08:00","A320",""],["RV","3","ZZ2","ZZ1","1234567","12:00","13:00","A320",""],
                  ["RV","5","ZZ2","ZZ1","1234567","18:00","19:00","A320",""],["RV","7","ZZ2","ZZ3","1234567","09:00","10:00","A320",""]]'),
    (s2, w, rv, '[]');
  perform set_config('equinox.actor', '', true), set_config('equinox.actor_detail', '', true);
  insert into t_cf values ('w', to_jsonb(w)), ('a1', to_jsonb(a1)), ('a2', to_jsonb(a2)), ('a3', to_jsonb(a3)), ('rv', to_jsonb(rv)),
                          ('m', to_jsonb('2030-01-15T12:00:00Z'::text));
end
$setup$;

-- ---------------------------------------------------------------- 2. the cash forecast
do $test$
declare
  a1 bigint := (select (v #>> '{}')::bigint from t_cf where k = 'a1');
  m timestamptz := (select (v #>> '{}')::timestamptz from t_cf where k = 'm');
  f jsonb; ta jsonb; tb jsonb; tc jsonb; o jsonb;
  near boolean;
begin
  f := public.cash_forecast(a1, '[]', m);
  insert into t_cf values ('fc', f);
  assert f ->> 'status' = 'ok', 'cash forecast: status ' || coalesce(f ->> 'status', 'none') || ', not ok';
  assert (f ->> 'cash')::numeric = 10 and f ->> 'cash_at' = '2030-01-15T11:00:00.000Z',
    format('cash forecast: cash %s at %s, not 10 at the capture''s time (the later capture must be left out)', f ->> 'cash', f ->> 'cash_at');
  assert (f ->> 'profit_per_flight')::numeric = 0.02 and (f ->> 'flights_per_day')::numeric = 2 and (f ->> 'flight_profit_day')::numeric = 0.04,
    format('cash forecast: %s a flight × %s flights a day = %s, not 0.02 × 2 = 0.04', f ->> 'profit_per_flight', f ->> 'flights_per_day', f ->> 'flight_profit_day');
  -- every payment after the capture (local time at the home airport to UTC), each in the first week again a week later
  assert (select jsonb_agg(jsonb_build_array(p ->> 'at', (p ->> 'amount')::numeric, (p ->> 'repeat')::boolean) order by i)
            from jsonb_array_elements(f -> 'payments') with ordinality as e(p, i))
       = jsonb_build_array(jsonb_build_array('2030-01-18T12:00:00.000Z', 1, false), jsonb_build_array('2030-01-20T12:00:00.000Z', 0.25, false),
                           jsonb_build_array('2030-01-21T00:00:00.000Z', 0.2, false), jsonb_build_array('2030-01-25T12:00:00.000Z', 1, true),
                           jsonb_build_array('2030-01-27T12:00:00.000Z', 0.25, true), jsonb_build_array('2030-01-28T00:00:00.000Z', 0.2, true)),
    'cash forecast: the payments and their weekly repeats aren''t as made: ' || (f -> 'payments')::text;
  assert (f ->> 'payments_next_7_days')::numeric = 1.45, 'cash forecast: payments in the next 7 days ' || (f ->> 'payments_next_7_days') || ', not 1.45';
  assert jsonb_array_length(f -> 'points') = 21, format('cash forecast: %s points, not 21 (6 payments and 15 days)', jsonb_array_length(f -> 'points'));
  -- the lowest point is at the last repeated lease's own moment: 10 + 0.04 × 12 13/24 − 2.9
  near := abs((f #>> '{lowest,balance}')::numeric - (10 + 0.04 * (12 + 13 / 24.0) - 2.9)) < 1e-9;
  assert f #>> '{lowest,at}' = '2030-01-28T00:00:00.000Z' and near,
    format('cash forecast: the lowest point is %s at %s, not 7.6017 at the repeated lease (2030-01-28 00:00)', f #>> '{lowest,balance}', f #>> '{lowest,at}');
  assert f #>> '{lowest,payment,at}' = '2030-01-28T00:00:00.000Z' and (f #>> '{lowest,payment,amount}')::numeric = 0.2
     and f #>> '{lowest,payment,what}' = 'Leasing payment for T1-002 (Test Jet B)' and (f #>> '{lowest,payment,repeat}')::boolean,
    'cash forecast: the payment that makes the lowest point isn''t the repeated lease at that moment: ' || (f #> '{lowest,payment}')::text;
  -- each type: price with its cabin, its lease (never leased: 10% of its price; leased: the highest payment seen), safe day, how many today
  select x into ta from jsonb_array_elements(f -> 'types') x where x ->> 'type' = 'TEST JET A';
  select x into tb from jsonb_array_elements(f -> 'types') x where x ->> 'type' = 'TEST JET B';
  select x into tc from jsonb_array_elements(f -> 'types') x where x ->> 'type' = 'TEST JET C';
  assert ta ->> 'cabin' = 'TA-LEI' and (ta ->> 'price_with_cabin')::numeric = 2.1 and (ta ->> 'lease_week')::numeric = 0.2
     and not (ta ->> 'lease_seen')::boolean, 'cash forecast: TEST JET A (never leased) isn''t 2.1 with its Leisure cabin, lease 0.2 (10%): ' || ta::text;
  assert tb ->> 'cabin' = 'TB-CMF' and (tb ->> 'price_with_cabin')::numeric = 3.2 and (tb ->> 'lease_week')::numeric = 0.25
     and (tb ->> 'lease_seen')::boolean, 'cash forecast: TEST JET B (leased) isn''t 3.2 with its Comfort cabin, lease 0.25 (the highest seen): ' || tb::text;
  assert tc ->> 'cabin' is null and (tc ->> 'price_with_cabin')::numeric = 7 and (tc ->> 'lease_week')::numeric = 0.7,
    'cash forecast: TEST JET C (no cabin layout) isn''t 7 with lease 0.7: ' || tc::text;
  -- today: 2 of A (3 would leave 0.27 at the 14-day point), 1 of B; C only from day 8, when its first lease falls past the 14 days
  assert (ta ->> 'safe_day')::int = 0 and (ta ->> 'count_today')::int = 2, format('cash forecast: TEST JET A safe day %s, %s today; not 0 and 2', ta ->> 'safe_day', ta ->> 'count_today');
  assert (tb ->> 'safe_day')::int = 0 and (tb ->> 'count_today')::int = 1, format('cash forecast: TEST JET B safe day %s, %s today; not 0 and 1', tb ->> 'safe_day', tb ->> 'count_today');
  assert (tc ->> 'safe_day')::int = 8 and tc ->> 'safe_from' = '2030-01-23T11:00:00.000Z' and tc ->> 'count_today' is null,
    format('cash forecast: TEST JET C safe from day %s (%s), not day 8 (2030-01-23 11:00)', tc ->> 'safe_day', tc ->> 'safe_from');
  assert f -> 'can_order_now' = '["TEST JET B", "TEST JET A"]'::jsonb and f #>> '{next_order,when}' = 'now',
    'cash forecast: can order now ' || (f -> 'can_order_now')::text || ', not B then A (dearest first)';
  -- two orders together, each with its own lease from 7 days after it is ordered: the lowest after is at the 14-day point,
  -- 7.66 − (2.1 + 3.2) − 2 × (0.2 + 0.25) = 1.46
  o := public.cash_forecast(a1, '[{"type": "TEST JET A", "count": 1}, {"type": "TEST JET B", "count": 1}]', m) -> 'orders_tested';
  assert (o ->> 'safe')::boolean and abs((o #>> '{lowest,balance}')::numeric - 1.46) < 1e-9 and o #>> '{lowest,at}' = '2030-01-29T11:00:00.000Z',
    'cash forecast: two orders together aren''t safe with 1.46 at the 14-day point: ' || o::text;
  assert (select count(*) from jsonb_array_elements(o -> 'orders') x where (x ->> 'may_buy')::boolean) = 2, 'cash forecast: the two orders aren''t both types One may buy';
  -- the forecast after them, point by point: before 7 days only their prices; from 7 days one lease each; at 14 days two
  assert jsonb_array_length(o -> 'points') = 21
     and (select abs((p ->> 'balance')::numeric - (10 + 0.04 * (3 + 1 / 24.0) - 1 - 5.3)) < 1e-9 from jsonb_array_elements(o -> 'points') p where p ->> 'at' = '2030-01-18T12:00:00.000Z')
     and (select abs((p ->> 'balance')::numeric - (10 + 0.04 * 7 - 1.45 - 5.3 - 0.45)) < 1e-9 from jsonb_array_elements(o -> 'points') p where p ->> 'at' = '2030-01-22T11:00:00.000Z')
     and (select abs((p ->> 'balance')::numeric - 1.46) < 1e-9 from jsonb_array_elements(o -> 'points') p where p ->> 'at' = '2030-01-29T11:00:00.000Z'),
    'cash forecast: the forecast after two orders doesn''t count each one''s lease from 7 days after it is ordered: ' || (o -> 'points')::text;
  o := public.cash_forecast(a1, '[{"type": "TEST JET A", "count": 2}]', m) -> 'orders_tested';
  assert (o ->> 'safe')::boolean, 'cash forecast: 2 × TEST JET A today isn''t safe';
  o := public.cash_forecast(a1, ('[{"aircraft_type_id": ' || (ta ->> 'aircraft_type_id') || ', "count": 3}]')::jsonb, m) -> 'orders_tested';
  assert not (o ->> 'safe')::boolean and abs((o #>> '{lowest,balance}')::numeric - (7.66 - 3 * 2.5)) < 1e-9,
    'cash forecast: 3 × TEST JET A today is safe, or its lowest point isn''t 0.16: ' || o::text;
  begin
    perform public.cash_forecast(a1, '[{"type": "NO SUCH JET"}]', m);
    raise exception 'refused?';
  exception when others then
    assert sqlerrm like 'p_orders: no such aircraft type%', 'cash forecast: an unknown type in p_orders isn''t refused by name: ' || sqlerrm;
  end;
  raise notice 'cash forecast: cash, flight profit, 6 payments with their weekly repeats, 21 points, the lowest point at a payment''s moment; A (never leased) 2 today, B (leased) 1, C from day 8; two orders together 1.46 at the lowest';
end
$test$;

do $test$
declare
  a1 bigint := (select (v #>> '{}')::bigint from t_cf where k = 'a1');
  a2 bigint := (select (v #>> '{}')::bigint from t_cf where k = 'a2');
  a3 bigint := (select (v #>> '{}')::bigint from t_cf where k = 'a3');
  m timestamptz := (select (v #>> '{}')::timestamptz from t_cf where k = 'm');
  f jsonb;
begin
  f := public.cash_forecast(a2, '[]', m);
  assert f ->> 'status' = 'no capture' and f ->> 'missing' like 'a capture%', 'cash forecast: an airline with no capture says ' || f::text;
  f := public.cash_forecast(a3, '[]', m);
  assert f ->> 'status' = 'missing' and f ->> 'missing' = 'a bank statement capture' and (f ->> 'cash')::numeric = 3,
    'cash forecast: an airline with 3 flights in its statement says ' || f::text;
  -- a moment before the capture: the day before's balance and nothing of the statement after it
  f := public.cash_forecast(a1, '[]', '2030-01-15 10:59:00+00');
  assert (f ->> 'cash')::numeric = 9 and f ->> 'cash_at' = '2030-01-14T11:00:00.000Z',
    'cash forecast: a moment before the capture doesn''t ignore it: ' || left(f::text, 300);
  f := public.cash_forecast(a1, '[]', '2030-01-14 10:00:00+00');
  assert f ->> 'status' = 'no capture', 'cash forecast: a moment before every capture of the week doesn''t say no capture: ' || left(f::text, 200);
  raise notice 'cash forecast: no capture and fewer than 5 flights say what''s missing; a moment before a capture ignores it';
end
$test$;

-- ---------------------------------------------------------------- 3. profit by day and the cards
do $test$
declare
  w bigint := (select (v #>> '{}')::bigint from t_cf where k = 'w');
  a1 bigint := (select (v #>> '{}')::bigint from t_cf where k = 'a1');
  m timestamptz := (select (v #>> '{}')::timestamptz from t_cf where k = 'm');
  p jsonb; c jsonb; one jsonb;
begin
  p := public.airline_profit(a1, m);
  -- 1 Jan: the typed 5M wins over the captured 4M (more than 7 days back); 14 Jan 9M; 15 Jan 10M (the later 50M left out)
  assert (select jsonb_agg(x ->> 'date' order by i) from jsonb_array_elements(p -> 'days') with ordinality as e(x, i)) = '["2030-01-14", "2030-01-15"]'::jsonb,
    'profit by day: the dates aren''t 14 and 15 Jan: ' || (p -> 'days')::text;
  assert (p #>> '{days,0,change}')::numeric = 4 and (p #>> '{days,0,days}')::int = 13 and (p #>> '{days,0,order_payments}')::numeric = 0.1
     and abs((p #>> '{days,0,profit_day}')::numeric - 4.1 / 13) < 1e-12,
    'profit by day: 1 to 14 Jan isn''t +4M (the typed figure wins) and the cabin''s 0.1M over 13 days: ' || (p #> '{days,0}')::text;
  assert (p #>> '{days,1,change}')::numeric = 1 and (p #>> '{days,1,order_payments}')::numeric = 2 and (p #>> '{days,1,profit_day}')::numeric = 3,
    'profit by day: 15 Jan isn''t +1M plus the 2M order (the loss stays in profit) = 3M: ' || (p #> '{days,1}')::text;
  assert (p #>> '{days,1,flights}')::int = 2 and (p #>> '{days,1,aircraft}')::int = 1, 'profit by day: 15 Jan doesn''t fly 2 flights on 1 aircraft';
  assert (p ->> 'profit_day')::numeric = 3 and (p ->> 'span_days')::int = 1 and (p ->> 'early')::boolean,
    'profit by day: the 7-day profit isn''t an early read of 3M a day over 1 day: ' || (p ->> 'profit_day');
  c := public.airline_cards(w, m);
  insert into t_cf values ('cards', c);
  assert (select jsonb_agg(x ->> 'name' order by i) from jsonb_array_elements(c -> 'airlines') with ordinality as e(x, i)) = '["One", "Two", "Three"]'::jsonb,
    'cards: not One, Two, Three in order: ' || left(c::text, 200);
  select x into one from jsonb_array_elements(c -> 'airlines') x where (x ->> 'airline_id')::bigint = a1;
  assert (one ->> 'profit_day')::numeric = 3 and (one ->> 'per_aircraft_day')::numeric = 3 and (one ->> 'fleet')::int = 1 and (one ->> 'on_order')::int = 1
     and (one ->> 'flights_day')::int = 2 and (one ->> 'fleet_value')::numeric = 2 and abs((one ->> 'return_on_fleet_pct_week')::numeric - 1050) < 1e-9
     and abs((one ->> 'payback_days')::numeric - 2 / 3.0) < 1e-12 and one ->> 'load_7_days' is null,
    'cards: One''s card isn''t 3M a day, 3M per aircraft, 1 flying and 1 on order, 2 flights, 1050% a week, pays back in 2/3 day: ' || one::text;
  assert one #> '{next_order}' = '{"when": "now", "types": ["TEST JET B", "TEST JET A"]}'::jsonb and one -> 'can_order_now' = '["TEST JET B", "TEST JET A"]'::jsonb,
    'cards: One''s next order isn''t "can order B or A": ' || (one -> 'next_order')::text;
  assert (select x -> 'next_order' from jsonb_array_elements(c -> 'airlines') x where x ->> 'name' = 'Two') = '{"when": "needs", "missing": "a capture"}'::jsonb
     and (select x -> 'next_order' from jsonb_array_elements(c -> 'airlines') x where x ->> 'name' = 'Three') = '{"when": "needs", "missing": "a bank statement capture"}'::jsonb,
    'cards: Two (no capture) and Three (3 flights) don''t say what they need';
  assert (select (x ->> 'cash')::numeric = 10 and (x ->> 'flight_profit_day')::numeric = 0.04 and abs((x ->> 'closing_day')::numeric - 1 / 7.0) < 1e-12
                 and abs((x ->> 'leases_day')::numeric - 0.45 / 7) < 1e-12 and x -> 'on_ground' = '[]'::jsonb
            from jsonb_array_elements(c -> 'group_today') x where (x ->> 'airline_id')::bigint = a1) and (c ->> 'group_today_shown')::boolean,
    'cards: One''s line of the group today isn''t 10M cash, 0.04M a day, the week''s closing and leases per day: ' || (c -> 'group_today')::text;
  raise notice 'profit by day: an order between two captures added back, a loss left in, a cabin counted, a typed figure kept; cards and the group today for One, Two and Three';
end
$test$;

-- ---------------------------------------------------------------- 4. route and aircraft profit, fare changes
do $test$
declare
  a1 bigint := (select (v #>> '{}')::bigint from t_cf where k = 'a1');
  m timestamptz := (select (v #>> '{}')::timestamptz from t_cf where k = 'm');
  r jsonb; x jsonb; t jsonb;
begin
  r := public.route_profit(a1, 7, m);
  assert (r ->> 'flights')::int = 6 and (r ->> 'matched')::int = 0 and jsonb_array_length(r -> 'routes') = 1,
    format('route profit: %s flights, %s matched, %s routes; not 6, 0 and 1', r ->> 'flights', r ->> 'matched', jsonb_array_length(r -> 'routes'));
  x := r -> 'routes' -> 0;
  assert x ->> 'hub' = 'ZZ1' and x ->> 'dest' = 'ZZ2' and (x ->> 'flights')::int = 6 and (x ->> 'profit')::numeric = 0.12
     and (x ->> 'profit_per_flight')::numeric = 0.02 and (x ->> 'flights_week')::int = 14 and (x ->> 'profit_week')::numeric = 0.28
     and (x ->> 'margin')::numeric = 0.4 and x ->> 'economy' is null and (x ->> 'with_loads')::int = 0 and x ->> 'sold_out_share' is null
     and x ->> 'mark' = 'hold', 'route profit: the route with no loads matched isn''t as made: ' || x::text;
  assert (public.route_profit(a1, 1, m) ->> 'flights')::int = 6, 'route profit: the last day doesn''t have the 6 flights';
  t := public.aircraft_profit(a1, 7, m) -> 'aircraft' -> 0;
  assert t ->> 'registration' = 'T1-001' and t ->> 'type' = 'TEST JET A' and (t ->> 'flights')::int = 6
     and (t ->> 'flight_profit_day')::numeric = 0.04 and abs((t ->> 'lease_day')::numeric - 0.25 / 7) < 1e-12
     and abs((t ->> 'net_day')::numeric - (0.04 - 0.25 / 7)) < 1e-12,
    'aircraft profit: T1-001 isn''t 0.02 × 2 flights a day less its 0.25M lease a week: ' || coalesce(t::text, 'none');
  assert public.fare_changes(a1, m) -> 'changes' = '[]'::jsonb, 'fare changes: one date of fares made a change';
  raise notice 'route profit: a route with no loads matched (6 flights, hold); aircraft profit with its lease; no fare change from one date';
end
$test$;

-- ---------------------------------------------------------------- 5. hubs first and the capture board
do $test$
declare
  w bigint := (select (v #>> '{}')::bigint from t_cf where k = 'w');
  a1 bigint := (select (v #>> '{}')::bigint from t_cf where k = 'a1');
  a3 bigint := (select (v #>> '{}')::bigint from t_cf where k = 'a3');
  m timestamptz := (select (v #>> '{}')::timestamptz from t_cf where k = 'm');
  h jsonb; one jsonb; b jsonb; c jsonb;
begin
  h := public.hub_progress(w, m);
  select x into one from jsonb_array_elements(h -> 'airlines') x where (x ->> 'airline_id')::bigint = a1;
  assert one ->> 'main_hub' = 'ZZ1' and (one ->> 'departures')::int = 7 and (one ->> 'planned')::int = 10 and (one ->> 'target')::int = 750
     and not (one ->> 'exempt')::boolean, 'hub progress: One''s main hub isn''t ZZ1 with 7 a week flying and 10 on its plan card: ' || one::text;
  assert (select (x ->> 'exempt')::boolean and x ->> 'main_hub' is null from jsonb_array_elements(h -> 'airlines') x where (x ->> 'airline_id')::bigint = a3),
    'hub progress: Three isn''t exempt (its own hub_first_exempt) with no main hub';
  b := one -> 'bases' -> 0;
  assert b ->> 'code' = 'ZZ2' and (b ->> 'contested_by_departures')::boolean and (b #>> '{top_rival,weekly}')::int = 300
     and b -> 'contested_routes' = ('[{"dest": "ZZ1", "name": "Rival Air", "weekly": 21, "airline_id": ' || (select v #>> '{}' from t_cf where k = 'rv') || '}]')::jsonb
     and (b ->> 'contested')::boolean, 'hub progress: ZZ2 isn''t contested by the rival''s 300 a week and ZZ2-ZZ1 three times a day (the scan by the moment): ' || b::text;
  c := public.capture_status(w, m);
  assert (select jsonb_agg(x ->> 'status' order by i) from jsonb_array_elements(c -> 'airlines') with ordinality as e(x, i)) = '["complete", "not captured", "missing"]'::jsonb,
    'capture board: One, Two and Three aren''t complete, not captured and missing: ' || left(c::text, 400);
  assert (select x #>> '{pages,balance,today}' = '2030-01-15T11:00:00.000Z' and x #>> '{pages,loads,yesterday}' = '2030-01-14T11:05:00.000Z'
                 and x #>> '{pages,statement,yesterday}' is null and (x ->> 'flights_today')::int = 1 and x ->> 'flights_yesterday' is null
            from jsonb_array_elements(c -> 'airlines') x where (x ->> 'airline_id')::bigint = a1),
    'capture board: One''s pages and flights aren''t as captured';
  assert (select x -> 'missing' from jsonb_array_elements(c -> 'airlines') x where (x ->> 'airline_id')::bigint = a3) = '["loads", "statement", "events", "pnl"]'::jsonb,
    'capture board: Three doesn''t miss loads, statement, events and pnl';
  raise notice 'hubs first: One''s main hub 7 flying and 10 planned, Three exempt, ZZ2 contested by departures and a route; the capture board for the three';
end
$test$;

-- ---------------------------------------------------------------- 6. who is refused; export_for_report('figures')
set local role anon;
do $test$
declare a1 bigint := (select (v #>> '{}')::bigint from t_cf where k = 'a1'); f text; n int := 0;
begin
  foreach f in array array['select public.cash_forecast(%s)', 'select public.airline_cards()', 'select public.airline_profit(%s)',
                           'select public.route_profit(%s)', 'select public.aircraft_profit(%s)', 'select public.growth_signals()',
                           'select public.hub_progress()', 'select public.capture_status()', 'select public.fare_changes(%s)'] loop
    begin execute format(f, a1); exception when insufficient_privilege then n := n + 1; end;
  end loop;
  assert n = 9, format('signed out, only %s of the 9 functions were refused', n);
end
$test$;
reset role;

do $$ begin perform set_config('request.jwt.claims',
  '{"sub": "00000000-0000-4000-8000-0000000000c1", "email": "captured-figures-other@example.com", "role": "authenticated"}', true); end $$;
set local role authenticated;
do $test$
declare a1 bigint := (select (v #>> '{}')::bigint from t_cf where k = 'a1'); f text; n int := 0;
begin
  foreach f in array array['select public.cash_forecast(%s)', 'select public.airline_cards()', 'select public.airline_profit(%s)',
                           'select public.route_profit(%s)', 'select public.aircraft_profit(%s)', 'select public.growth_signals()',
                           'select public.hub_progress()', 'select public.capture_status()', 'select public.fare_changes(%s)'] loop
    begin execute format(f, a1); exception when insufficient_privilege then n := n + 1; end;
  end loop;
  assert n = 9, format('an account that isn''t staff had only %s of the 9 functions refused', n);
end
$test$;
reset role;

do $$ begin perform set_config('request.jwt.claims',
  '{"sub": "00000000-0000-4000-8000-0000000000c2", "email": "captured-figures-staff@example.com", "role": "authenticated"}', true); end $$;
set local role authenticated;
do $test$
declare w bigint := (select (v #>> '{}')::bigint from t_cf where k = 'w'); m timestamptz := (select (v #>> '{}')::timestamptz from t_cf where k = 'm');
begin
  assert public.airline_cards(w, m) = (select v from t_cf where k = 'cards'), 'staff don''t get what postgres gets from airline_cards()';
  assert public.cash_forecast((select (v #>> '{}')::bigint from t_cf where k = 'a1'), '[]', m) = (select v from t_cf where k = 'fc'),
    'staff don''t get what postgres gets from cash_forecast()';
end
$test$;
reset role;
do $test$ begin raise notice 'signed out and an account that isn''t staff are refused by all 9; staff get what postgres gets'; end $test$;

insert into t_cf values ('secret', to_jsonb('captured-figures-test-' || gen_random_uuid()::text));
insert into public.ingest_secret (secret) select v #>> '{}' from t_cf where k = 'secret';
set local role anon;
do $test$
declare s text := (select v #>> '{}' from t_cf where k = 'secret'); w text := (select v #>> '{}' from t_cf where k = 'w');
  d jsonb; refused boolean := false;
begin
  d := public.export_for_report(s, 'figures', format('{"world": %s, "as_of": "2030-01-15T12:00:00Z"}', w));
  assert d ?& array['world_id', 'as_of', 'airline_cards', 'growth_signals', 'hub_progress', 'capture_status', 'airlines'],
    'export_for_report(figures) leaves a function out: ' || (select string_agg(k, ', ') from jsonb_object_keys(d) k);
  assert d -> 'airline_cards' = (select v from t_cf where k = 'cards'), 'export_for_report(figures)''s cards differ from airline_cards()';
  assert jsonb_array_length(d -> 'airlines') = 3
     and (select bool_and(x ?& array['cash_forecast', 'airline_profit', 'route_profit', 'aircraft_profit', 'fare_changes']
                          and x -> 'route_profit' ?& array['1', '3', '7']) from jsonb_array_elements(d -> 'airlines') x),
    'export_for_report(figures) doesn''t give every function for each of the three airlines';
  assert d -> 'airlines' -> 0 -> 'cash_forecast' = (select v from t_cf where k = 'fc'), 'export_for_report(figures)''s forecast differs from cash_forecast()';
  begin perform public.export_for_report(s || '-wrong', 'figures'); exception when others then refused := sqlerrm = 'not allowed'; end;
  assert refused, 'export_for_report(figures) with a wrong secret wasn''t refused';
end
$test$;
reset role;
do $test$ begin raise notice 'export_for_report(secret, figures), signed out as the scripts call it, answers every function for every airline; a wrong secret is refused'; end $test$;

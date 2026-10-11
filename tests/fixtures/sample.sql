-- The test sample (decision #9): what the planner and the website read at one moment, as one JSON document. Run with
-- psql -v at=<moment, UTC> on a copy of the database, by tests/fixtures/make_sample.sh or database/rehearse.sh.
-- Since the switch-over (#13, pull request 9) the planner reads its document and loads from the tables, through the
-- adapter's getters, so the sample does too: planner_state is planner_state_get()'s document and planner_loads is
-- planner_loads_get()'s months. It also carries settings, world_rules and planner_meta's growth rules, for the rule
-- numbers check (tests/rule_numbers_test.py). The other reads are the planner's capture board's, with "today" = the
-- moment. Never keys or sign-in data.
with t as (select :'at'::timestamptz as at, (:'at'::timestamptz at time zone 'utc')::date as d),
bal as (select airline, captured_on, amount, captured_at from game_balance, t
        where account like '2800%' and captured_on >= t.d - 7 order by captured_at desc)
select json_build_object(
  'frozen_at', (select at from t),
  'made_from', 'nightly backup, read as of ' || (select at from t) || '; the planner''s document and loads from planner_state_get() and planner_loads_get()',
  'planner_state', ((public.planner_state_get() ->> 'json')::json),
  'planner_loads', (select coalesce(json_agg(json_build_object('month', g.month, 'json', g.json, 'saved_at', g.saved_at) order by g.month), '[]') from public.planner_loads_get() g),
  'planner_data', (select value from planner_data where key = 'DATA'),
  'site_public', (select public.site_public()),
  'settings', (select coalesce(json_agg(json_build_object('key', s.key, 'airline', al.planner_name, 'value', s.value) order by s.key, al.planner_name), '[]')
                 from public.settings s left join public.airlines al on al.id = s.airline_id
                where s.world_id = (select id from public.worlds where is_default)),
  'world_rules', (select coalesce(json_agg(json_build_object('key', r.key, 'value', r.value) order by r.key), '[]')
                    from public.world_rules r where r.world_id = (select id from public.worlds where is_default)),
  'planner_meta', json_build_object('growthRules', (select value from planner_meta where key = 'growthRules')),
  'tables', json_build_object(
    'game_capture_raw', (select coalesce(json_agg(r order by r.captured_at desc), '[]') from (select airline, kind, captured_at from game_capture_raw, t where captured_at >= (t.d - 2)::timestamptz) r),
    'game_loads', (select coalesce(json_agg(r), '[]') from (select airline,flight_date,code,tail,origin,dest,dep_time,arr_time,eco,bus,fst,cargo,eco_pax,eco_seats,bus_pax,bus_seats,fst_pax,fst_seats,eco_fare,bus_fare from game_loads, t where flight_date >= t.d - 9) r),
    'game_flight_pnl', (select coalesce(json_agg(r), '[]') from (select airline,ts,blk,route,routes_n,pax,tail,pax_income,cargo_income,fuel,onboard,handling,landing,atc,maintenance,profit from game_flight_pnl, t where ts >= (t.d - 8)::timestamptz) r),
    'game_balance', (select coalesce(json_agg(bal), '[]') from bal),
    'game_events', (select coalesce(json_agg(r), '[]') from (select airline,event_date,event_time,debit,descr from game_events, t
        where event_date >= coalesce((select min(captured_on) from bal), t.d - 7) and event_date <= t.d + 16) r),
    'game_ops_recent', (select coalesce(json_agg(r), '[]') from (select airline,flights,income,costs,hours,last_ts from game_ops_recent) r),
    'backup_runs', (select coalesce(json_agg(r order by r.ran_at desc), '[]') from (select ran_at,kind,ok,tables,rows,files,bytes,note from backup_runs order by ran_at desc limit 10) r)
  ));

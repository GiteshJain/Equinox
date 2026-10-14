-- The daily history and the world-scan tables (#13 build, pull request 6; design §3.9, §3.10, §5, §7, §9 step 4): who
-- can reach them, and the backfill. Run by database/rehearse.sh on the copy of last night's backup, after the new
-- migrations (both files: the adding one and the removal Gitesh runs), inside a transaction that is rolled back. A
-- failed check stops with an error that says which (dates, airlines and counts, never figures).
--   1. From the catalogue: the eight tables have RLS on with one staff read rule (checked once per query); anon holds
--      nothing on them; authenticated may only read them; none is in the change log; every foreign key has an index;
--      the new internal functions are closed; ingest_snapshot() and export_for_report() are called as before (signed
--      out, with the ingest secret), run as owner with an empty search path. Signed in but not staff: no rows; staff:
--      every row.
--   2. The backfill, checked exactly on the night it runs (the rehearsal's copy didn't have the history yet):
--      - every active airline of ours has a day from 29 Sep to the last capture day that had ended, marked backfill,
--        complete exactly when the day's capture was;
--      - cash: from 7 Oct, the capture day's latest balance (account 2800) and its time (until the clean-up, build pull
--        request 14, also against the old planner's stored figures, which went with planner_state);
--      - flights per day from game_flights (every flight that departed that UTC day, from 6 Oct; none before), and the
--        route days add up to them;
--      - the fleet on today's date as aircraft has it (flying = active and delivered; on order = on_order), by type,
--        and each day's fleet and weekly departures from the delivery and launch dates;
--      On later nights the history is the snapshots' and only what still holds is checked: every day's cash is the
--      balance it names (unless a later capture the same UTC date has since replaced that balance), and the fleet rule
--      agrees with aircraft today.

create temporary table t_hist (name text primary key) on commit drop;
insert into t_hist values ('airline_days'), ('route_days'), ('game_scans'), ('game_scan_airlines'), ('game_scan_schedules'),
  ('game_scan_airports'), ('scan_airline_airports'), ('scan_airline_markets');
grant select on t_hist to authenticated;

-- ---------------------------------------------------------------- 1. the catalogue
do $test$
declare bad text;
begin
  select string_agg(t.name, ', ') into bad from t_hist t where to_regclass('public.' || t.name) is null;
  assert bad is null, 'missing tables: ' || bad;
  select string_agg(t.name, ', ') into bad from t_hist t join pg_class c on c.oid = ('public.' || t.name)::regclass
   where not c.relrowsecurity;
  assert bad is null, 'RLS is off on: ' || bad;
  select string_agg(t.name || ' (' || coalesce(p.rules, 'none') || ')', ', ') into bad
    from t_hist t left join lateral (
      select string_agg(lower(cmd) || ' ' || array_to_string(roles, '+') || ' ' || coalesce(qual, ''), '; ') as rules
        from pg_policies where schemaname = 'public' and tablename = t.name) p on true
   where p.rules is distinct from 'select authenticated ( SELECT is_planner_user() AS is_planner_user)';
  assert bad is null, 'not exactly one staff read rule on: ' || bad;
  select string_agg(t.name || ' ' || p.priv, ', ') into bad
    from t_hist t cross join unnest(array['select', 'insert', 'update', 'delete', 'truncate', 'references', 'trigger']) as p(priv)
   where has_table_privilege('anon', 'public.' || t.name, p.priv);
  assert bad is null, 'anon holds: ' || bad;
  select string_agg(t.name || ' ' || p.priv, ', ') into bad
    from t_hist t cross join unnest(array['insert', 'update', 'delete', 'truncate', 'references', 'trigger']) as p(priv)
   where has_table_privilege('authenticated', 'public.' || t.name, p.priv);
  assert bad is null, 'authenticated can write: ' || bad;
  select string_agg(t.name, ', ') into bad from t_hist t where not has_table_privilege('authenticated', 'public.' || t.name, 'select');
  assert bad is null, 'staff can''t read: ' || bad;
  -- not in the change log (design §6: dated already, or derived)
  select string_agg(t.name, ', ') into bad from t_hist t
   where exists (select 1 from pg_trigger g where g.tgrelid = ('public.' || t.name)::regclass and g.tgfoid = 'private.log_change()'::regprocedure);
  assert bad is null, 'in the change log: ' || bad;
  -- every foreign key has an index that starts with one of its columns (design §2)
  select string_agg(c.conrelid::regclass::text || ' (' || c.conname || ')', ', ') into bad
    from pg_constraint c join t_hist t on c.conrelid = ('public.' || t.name)::regclass
   where c.contype = 'f' and not exists (select 1 from pg_index i where i.indrelid = c.conrelid and i.indkey[0] = any (c.conkey));
  assert bad is null, 'foreign keys without an index: ' || bad;
  -- the internal functions are closed and run as the caller; the scripts' two run as owner, for anyone with the secret
  select string_agg(p.oid::regprocedure::text, ', ') into bad from pg_proc p
   where p.oid in ('private.history_fleet(bigint, timestamptz)'::regprocedure, 'private.history_schedule(bigint, date)'::regprocedure,
                   'private.history_cash(bigint, date, timestamptz)'::regprocedure, 'private.history_flows(bigint, date, date)'::regprocedure,
                   'private.take_snapshot(bigint, date, timestamptz, text, boolean)'::regprocedure,
                   'private.snapshot_due(bigint, date, timestamptz)'::regprocedure, 'private.scan_airline(bigint, integer, text)'::regprocedure,
                   'private.scan_summarise(bigint)'::regprocedure, 'private.capture_store(bigint, text, text, text, jsonb, timestamptz, boolean)'::regprocedure,
                   'private.capture_page(bigint)'::regprocedure)
     and (p.prosecdef or has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute')
          or not coalesce('search_path=""' = any (p.proconfig), false));
  assert bad is null, 'internal functions open, run as owner or without an empty search path: ' || bad;
  select string_agg(p.oid::regprocedure::text, ', ') into bad from pg_proc p
   where p.oid in ('public.ingest_snapshot(text, text, jsonb)'::regprocedure, 'public.export_for_report(text, text, text)'::regprocedure)
     and not (p.prosecdef and coalesce('search_path=""' = any (p.proconfig), false)
              and has_function_privilege('anon', p.oid, 'execute') and has_function_privilege('authenticated', p.oid, 'execute'));
  assert bad is null, 'not callable as before, or not as owner with an empty search path: ' || bad;
  raise notice 'the history and scan tables (%): RLS with one staff read rule, anon nothing, authenticated read only, not in the change log; every foreign key indexed; the new internal functions closed',
    (select string_agg(name, ', ' order by name) from t_hist);
end
$test$;

-- ---------------------------------------------------------------- signed in, but not staff: nothing
do $$ begin perform set_config('request.jwt.claims',
  '{"sub": "00000000-0000-4000-8000-0000000000c2", "email": "history-not-staff@example.com", "role": "authenticated"}', true); end $$;
set local role authenticated;
do $test$
declare r record; n bigint;
begin
  assert not public.is_planner_user(), 'the test account is staff';
  for r in select name from t_hist loop
    execute format('select count(*) from public.%I', r.name) into n;
    assert n = 0, format('an account that isn''t staff reads %s row(s) of %s', n, r.name);
  end loop;
end
$test$;
reset role;
create temporary table t_staff_counts (name text primary key, n bigint) on commit drop;
grant insert on t_staff_counts to authenticated;
insert into public.planner_users (email) values ('history-staff@example.com') on conflict do nothing;
do $$ begin perform set_config('request.jwt.claims',
  '{"sub": "00000000-0000-4000-8000-0000000000c1", "email": "history-staff@example.com", "role": "authenticated"}', true); end $$;
set local role authenticated;
do $test$
declare r record; n bigint;
begin
  assert public.is_planner_user(), 'the test account isn''t staff';
  for r in select name from t_hist loop
    execute format('select count(*) from public.%I', r.name) into n;
    insert into t_staff_counts values (r.name, n);
  end loop;
end
$test$;
reset role;
do $test$
declare bad text; n bigint;
begin
  for bad in select t.name from t_staff_counts t loop
    execute format('select count(*) from public.%I', bad) into n;
    assert n = (select x.n from t_staff_counts x where x.name = bad), format('staff read %s of the %s rows of %s', (select x.n from t_staff_counts x where x.name = bad), n, bad);
  end loop;
end
$test$;

-- ---------------------------------------------------------------- 2. the backfill
do $test$
declare
  w bigint := (select id from public.worlds where is_default);
  v_strict boolean;
  v_last date; v_first_flight date; bad text; n bigint; n2 bigint; n3 bigint; n4 bigint; v_super bigint := 0; v_typed bigint := 0;
  n_stored bigint;
  st jsonb;
begin
  -- the night the history is filled back: the copy had no history before the migration
  -- (with no saved answer, as when this file is run on its own, the night is taken to be the backfill's)
  if to_regclass('rehearsal_before.history_tables') is not null then
    execute 'select not existed from rehearsal_before.history_tables limit 1' into v_strict;
  end if;
  v_strict := coalesce(v_strict, true);
  select max(day) into v_last from public.airline_days where world_id = w and source = 'backfill';
  assert v_last is not null, 'no backfilled days';

  -- the fleet rule agrees with aircraft today, airline by airline and type by type (every night)
  select string_agg(al.planner_name, ', ') into bad
    from private.history_fleet(w, now()) f join public.airlines al on al.id = f.airline_id
   where f.aircraft_total <> (select count(*) from public.aircraft a where a.airline_id = f.airline_id and a.status in ('active', 'delivered'))
      or f.on_order <> (select count(*) from public.aircraft a where a.airline_id = f.airline_id and a.status = 'on_order')
      or f.aircraft_by_type is distinct from
         (select coalesce(jsonb_object_agg(x.name, x.n), '{}'::jsonb)
            from (select coalesce(t.name, '(no type)') as name, count(*)::int as n from public.aircraft a
                    left join public.aircraft_types t on t.id = a.aircraft_type_id
                   where a.airline_id = f.airline_id and a.status in ('active', 'delivered') group by 1) x);
  assert bad is null, 'the fleet on today''s date differs from aircraft for: ' || bad;

  -- every day's cash is the balance it names (every night): its time is a kept balance's with that figure, unless a later
  -- capture the same UTC date has replaced that balance since
  select count(*) filter (where b.amount is distinct from d.cash), count(*) filter (where b.amount is null)
    into n, v_super
    from public.airline_days d
    left join public.game_balance b on b.airline_id = d.airline_id and b.account like '2800%' and b.captured_at = d.cash_at
   where d.world_id = w and d.cash_at is not null;
  assert n = v_super, format('%s days'' cash isn''t the balance of the time they name', n - v_super);

  if not v_strict then
    raise notice 'backfill: the history was there before this rehearsal, so only what still holds was checked (the fleet rule against aircraft today; every day''s cash against its balance, % replaced since by a later capture the same UTC date)', v_super;
    return;
  end if;

  -- days: every active airline of ours, 29 Sep to the last day, backfilled, complete exactly when the capture was
  select string_agg(format('%s %s', al.planner_name, g.d::date), ', ') into bad
    from public.airlines al join public.groups gr on gr.id = al.group_id and gr.world_id = al.world_id
    cross join generate_series(date '2026-09-29', v_last, interval '1 day') g(d)
   where al.world_id = w and al.active and gr.kind = 'ours'
     and not exists (select 1 from public.airline_days d where d.airline_id = al.id and d.day = g.d::date and d.source = 'backfill'
                       and d.complete = private.capture_day_complete(w, g.d::date));
  assert bad is null, 'missing or wrongly marked backfilled days: ' || left(bad, 400);
  assert v_last >= private.capture_day(w, now()) - 1, format('the backfill stops at %s, before the last capture day that has ended', v_last);

  -- cash from 7 Oct: the capture day's latest balance and its time, or (with none) a typed figure
  select count(*) into n2 from public.airline_days d
    left join lateral (select b.amount, b.captured_at from public.game_balance b
                        where b.airline_id = d.airline_id and b.capture_day = d.day and b.account like '2800%' and b.amount is not null
                        order by b.captured_at desc limit 1) lb on true
   where d.world_id = w and d.source = 'backfill' and d.day >= date '2026-10-07'
     and (d.cash, d.cash_at) is distinct from (lb.amount, lb.captured_at)
     and not (lb.captured_at is null and d.cash_at is null);
  assert n2 = 0, format('%s backfilled days from 7 Oct don''t have their capture day''s latest balance', n2);

  -- flights per day: every flight that departed that UTC day, from 6 Oct (none counted before)
  select min(coalesce((f.dep_at at time zone 'UTC')::date, f.game_date)) into v_first_flight from public.game_flights f where f.world_id = w;
  select string_agg(format('%s %s: %s, game_flights %s', al.planner_name, d.day, d.flights_flown, x.n), '; ') into bad
    from public.airline_days d join public.airlines al on al.id = d.airline_id
    cross join lateral (select count(*) as n from public.game_flights f
                         where f.airline_id = d.airline_id and (f.flight_no is not null or f.pax_income is not null)
                           and coalesce((f.dep_at at time zone 'UTC')::date, f.game_date) = d.day) x
   where d.world_id = w and d.day >= date '2026-10-06' and d.flights_flown is distinct from x.n::int;
  assert bad is null, 'flights per day differ from game_flights: ' || left(bad, 400);
  select count(*) into n from public.airline_days d where d.world_id = w and d.day < date '2026-10-06' and d.flights_flown is not null;
  assert n = 0, format('%s days before 6 Oct have flights counted', n);
  select string_agg(format('%s %s', d.airline_id, d.day), ', ') into bad
    from public.airline_days d
   where d.world_id = w and d.day >= date '2026-10-06'
     and d.flights_flown <> coalesce((select sum(r.flights) from public.route_days r where r.airline_id = d.airline_id and r.day = d.day), 0)
                          + (select count(*) from public.game_flights f
                              where f.airline_id = d.airline_id and (f.flight_no is not null or f.pax_income is not null)
                                and coalesce((f.dep_at at time zone 'UTC')::date, f.game_date) = d.day
                                and (coalesce(f.origin_code, '') = '' or coalesce(f.dest_code, '') = ''));
  assert bad is null, 'the route days don''t add up to the day''s flights for: ' || left(bad, 400);
  select count(*) into n from public.game_flights f
   where f.world_id = w and (f.flight_no is not null or f.pax_income is not null) and coalesce(f.origin_code, '') <> '' and coalesce(f.dest_code, '') <> ''
     and coalesce((f.dep_at at time zone 'UTC')::date, f.game_date) >= date '2026-10-06';
  assert n = (select coalesce(sum(r.flights), 0) from public.route_days r where r.world_id = w and r.day >= date '2026-10-06'),
    'route_days doesn''t hold every flight from 6 Oct';

  -- the fleet and the schedule on each day, from the delivery and launch dates
  select string_agg(format('%s %s', al.planner_name, d.day), ', ') into bad
    from public.airline_days d join public.airlines al on al.id = d.airline_id
    left join private.history_fleet(w, d.taken_at) f on f.airline_id = d.airline_id
   where d.world_id = w and d.source = 'backfill'
     and ((d.aircraft_total, d.on_order, d.aircraft_by_type) is distinct from (f.aircraft_total, f.on_order, f.aircraft_by_type)
          or d.aircraft_total <> (select count(*) from public.aircraft a
                                   where a.airline_id = d.airline_id and a.status in ('active', 'delivered', 'retired')
                                     and (a.delivery_at is null or a.delivery_at <= d.taken_at)
                                     and not (a.status = 'retired' and (a.retired_on is null or a.retired_on <= d.day)))
          or d.weekly_departures <> (select coalesce(sum(cardinality(l.days_utc)), 0) from public.flight_legs l
                                       join public.rotations r on r.id = l.rotation_id
                                      where r.airline_id = d.airline_id and (r.launched_on is null or r.launched_on <= d.day)));
  assert bad is null, 'backfilled fleet or weekly departures differ from the delivery and launch dates for: ' || left(bad, 400);

  raise notice 'backfill: % airline days, 29 Sep to %, each airline every day; cash each capture day''s latest balance from 7 Oct',
    (select count(*) from public.airline_days where world_id = w), v_last;
  raise notice 'backfill: flights per day from game_flights for every day from 6 Oct (first flight data %), % route days add up to them; the fleet today as aircraft has it',
    v_first_flight, (select count(*) from public.route_days where world_id = w);
end
$test$;

do $$ begin raise notice 'daily history and backfill: all checks passed'; end $$;

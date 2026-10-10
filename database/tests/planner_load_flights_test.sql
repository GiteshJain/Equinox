-- The flight rules and the matching after the planner's data loaded (#13 build, pull request 4; design §3.8, §4). Run by
-- database/rehearse.sh on the copy of last night's backup, after the new migrations, inside a transaction that is rolled
-- back. A failed check stops with an error naming the frequencies (by their old id) or the counts.
--   1. Every frequency in planner_state is a rotation with two legs whose UTC weekdays, departure minutes and block times
--      give back the frequency's local days and times exactly, and its flight numbers; and every return departs within
--      24 hours of its outbound's arrival, at the first departure after it: the old planner's rule (the local day the
--      outbound arrives, or the next day if it leaves earlier than that arrival), checked here in UTC across the week.
--   2. Design §4's worked example, Kingfisher's DEL-JFK frequency z5qbaeg, while it still flies as on 8 Oct.
--   3. Matching after the refresh: the share of game_flights rows with both money and loads, before and after, and the
--      rows left one-sided with the reason; and how many flights have their route and aircraft.

create temporary table t_freq on commit drop as
select f.v ->> 'id' as k, f.v, r.id as rotation_id,
       l1.days_utc as d1, l1.dep_utc_min as dep1, l1.block_min as b1, l1.flight_no as no1, l1.origin_code as o1, l1.dest_code as t1,
       l2.days_utc as d2, l2.dep_utc_min as dep2, l2.block_min as b2, l2.flight_no as no2, l2.origin_code as o2, l2.dest_code as t2,
       round(coalesce(wh.utc_offset_override, ah.utc_offset, 0) * 60)::int as oh,
       round(coalesce(wd.utc_offset_override, ad.utc_offset, 0) * 60)::int as od,
       private.clock_min(f.v ->> 'depHub') as dep_hub, private.clock_min(f.v ->> 'arrDest') as arr_dest,
       private.clock_min(f.v ->> 'depDest') as dep_dest, private.clock_min(f.v ->> 'arrHub') as arr_hub,
       private.weekday_set(f.v ->> 'days') as days_local
  from public.planner_state p
  cross join lateral jsonb_array_elements(p.json::jsonb -> 'freqs') as f(v)
  left join public.rotations r on r.world_id = (select id from public.worlds where is_default) and r.legacy_key = f.v ->> 'id'
  left join public.routes ro on ro.id = r.route_id
  left join public.flight_legs l1 on l1.rotation_id = r.id and l1.leg_no = 1
  left join public.flight_legs l2 on l2.rotation_id = r.id and l2.leg_no = 2
  left join public.airports ah on ah.code = ro.hub_code
  left join public.world_airports wh on wh.world_id = r.world_id and wh.airport_code = ro.hub_code
  left join public.airports ad on ad.code = ro.dest_code
  left join public.world_airports wd on wd.world_id = r.world_id and wd.airport_code = ro.dest_code
 where p.id = 'main';

-- ---------------------------------------------------------------- 1. every frequency, and every return's day
do $test$
declare bad text; n bigint; n_timed bigint; n_next bigint;
begin
  select string_agg(k, ', ') into bad from t_freq where rotation_id is null or d1 is null or d2 is null;
  assert bad is null, 'frequencies with no rotation or no two legs: ' || bad;
  -- local times and days at each end, from the legs' UTC ones
  select string_agg(k, ', ') into bad from t_freq
   where dep_hub is distinct from (case when dep1 is not null then ((dep1 + oh) % 1440 + 1440) % 1440 end)
      or (dep_hub is not null and arr_dest is distinct from ((dep1 + b1 + od) % 1440 + 1440) % 1440)
      or dep_dest is distinct from (case when dep2 is not null then ((dep2 + od) % 1440 + 1440) % 1440 end)
      or (dep_dest is not null and arr_hub is distinct from ((dep2 + b2 + oh) % 1440 + 1440) % 1440)
      or coalesce(days_local, '{1,2,3,4,5,6,7}') is distinct from
         private.shift_weekdays(d1, case when dep1 is not null then floor((dep1 + oh) / 1440.0)::int else 0 end);
  assert bad is null, 'legs whose UTC weekdays, departure or block don''t give back the frequency''s local days and times: ' || bad;
  select string_agg(k, ', ') into bad from t_freq
   where no1 is distinct from private.json_int(v -> 'noOut') or no2 is distinct from private.json_int(v -> 'noBack');
  assert bad is null, 'legs whose flight numbers differ from the frequency''s: ' || bad;
  -- the return: each outbound landing (UTC, minutes into the week) is followed within 24 hours by exactly one return
  -- departure, and there are as many returns as outbounds
  select count(*) into n_timed from t_freq where dep_hub is not null and arr_dest is not null and dep_dest is not null;
  select string_agg(k, ', ') into bad from t_freq t
   where t.dep_hub is not null and t.arr_dest is not null and t.dep_dest is not null
     and (cardinality(t.d1) <> cardinality(t.d2)
          or exists (select 1 from unnest(t.d1) as a(d)
                      where (select count(*) from unnest(t.d2) as b(e)
                              where ((((e - 1) * 1440 + t.dep2) - (((d - 1) * 1440 + t.dep1 + t.b1) % 10080)) % 10080 + 10080) % 10080 < 1440) <> 1));
  assert bad is null, 'returns that don''t follow the old planner''s rule (the first departure within 24 hours of the outbound''s landing): ' || bad;
  -- (how many of them leave on the next local day: the old planner's "earlier than the arrival" case)
  select count(*) into n_next from t_freq where dep_dest is not null and arr_dest is not null and dep_dest < arr_dest;
  select count(*) into n from t_freq;
  raise notice 'flight rules: % frequencies, % legs: every leg gives back its frequency''s local days, times and numbers; % returns timed, each the first departure within 24 hours of its outbound''s landing (% of them the next local day); % not fully timed',
    n, 2 * n, n_timed, n_next, n - n_timed;
end
$test$;

-- ---------------------------------------------------------------- 2. design §4's worked example
do $test$
declare t record; v record;
begin
  select * into t from t_freq where k = 'z5qbaeg';
  if t is null or t.v ->> 'routeKey' <> 'Kingfisher|DEL|JFK' or t.v ->> 'days' <> '135' or t.v ->> 'depHub' <> '01:30'
     or t.v ->> 'arrDest' <> '04:19' or t.v ->> 'depDest' <> '07:30' or t.v ->> 'arrHub' <> '07:19' or t.oh <> 330 or t.od <> -300 then
    raise notice 'DEL-JFK z5qbaeg no longer flies as on 8 Oct; design §4''s example is checked on the frozen sample instead';
    return;
  end if;
  assert t.o1 = 'DEL' and t.t1 = 'JFK' and t.no1 = 1001 and t.d1 = '{2,4,7}' and t.dep1 = 1200 and t.b1 = 799,
    format('z5qbaeg leg 1 is %s-%s %s on %s at %s for %s min, expected DEL-JFK 1001 on {2,4,7} at 1200 for 799', t.o1, t.t1, t.no1, t.d1, t.dep1, t.b1);
  assert t.o2 = 'JFK' and t.t2 = 'DEL' and t.no2 = 1002 and t.d2 = '{1,3,5}' and t.dep2 = 750 and t.b2 = 799,
    format('z5qbaeg leg 2 is %s-%s %s on %s at %s for %s min, expected JFK-DEL 1002 on {1,3,5} at 750 for 799', t.o2, t.t2, t.no2, t.d2, t.dep2, t.b2);
  select * into v from public.flight_legs_local where rotation_id = t.rotation_id and leg_no = 2;
  assert v.dep_local = '07:30' and v.days_local = '{1,3,5}' and v.arr_local = '07:19' and v.arr_local_day_offset = 1,
    'z5qbaeg''s return doesn''t read back as Mon, Wed, Fri 07:30 -> 07:19 the next day';
  raise notice 'DEL-JFK z5qbaeg as design §4: leg 1 {2,4,7} 20:00 UTC, 799 min; leg 2 {1,3,5} 12:30 UTC, 799 min; read back Mon, Wed, Fri 01:30 -> 04:19 and 07:30 -> 07:19 the next day';
end
$test$;

-- ---------------------------------------------------------------- 3. matching after the refresh
do $test$
declare b bigint; m bigint; l bigint; total bigint; v_before text; v_money text; v_loads text; v_links text;
begin
  select count(*) filter (where flight_no is not null and posted_at is not null), count(*) filter (where flight_no is null),
         count(*) filter (where posted_at is null), count(*)
    into b, m, l, total from public.game_flights;
  v_before := coalesce((select format('%s both, %s money only, %s loads only', both_sides, money_only, loads_only)
                          from rehearsal_before.game_flights_sides limit 1), 'no game_flights yet');
  -- why a row is still one-sided
  with mo as (select * from public.game_flights where flight_no is null),
  lo as (select * from public.game_flights where posted_at is null),
  why_m as (
    select case when mo.statement_routes <> 1 then 'names no single route'
                when not exists (select 1 from public.game_flights x where x.airline_id = mo.airline_id and x.flight_no is not null
                                    and x.origin_code = mo.origin_code and x.dest_code = mo.dest_code
                                    and mo.posted_at - x.dep_at between interval '-30 minutes' and interval '3 hours')
                  then 'no loads captured for it'
                else 'its loads row paired with a nearer block' end as why
      from mo),
  why_l as (
    select case when lo.dep_at is null then 'departure time unknown'
                when lo.dep_at > (select max(s.ts) from public.game_statement s where s.airline_id = lo.airline_id) - interval '30 minutes'
                  then 'not on a statement yet'
                when lo.dep_at < (select min(s.ts) from public.game_statement s where s.airline_id = lo.airline_id) - interval '3 hours'
                  then 'before the first statement captured'
                when not exists (select 1 from public.game_flights x where x.airline_id = lo.airline_id and x.posted_at is not null
                                    and x.origin_code = lo.origin_code and x.dest_code = lo.dest_code
                                    and x.posted_at - lo.dep_at between interval '-30 minutes' and interval '3 hours')
                  then 'no statement block on its route within 3 hours'
                else 'its block paired with a nearer flight' end as why
      from lo)
  select (select string_agg(why || ' ' || n, ', ' order by n desc) from (select why, count(*) n from why_m group by why) x),
         (select string_agg(why || ' ' || n, ', ' order by n desc) from (select why, count(*) n from why_l group by why) x)
    into v_money, v_loads;
  select format('%s of %s rows have their route, %s their aircraft', count(route_id), count(*), count(aircraft_id)) into v_links
    from public.game_flights;
  raise notice 'matching after the refresh: % of % game_flights rows have both money and loads (% %%; before: %); one-sided: % money only (%), % loads only (%); %',
    b, total, case when total > 0 then round(100.0 * b / total, 1) else 0 end, v_before, m, coalesce(v_money, 'none'), l, coalesce(v_loads, 'none'), v_links;
end
$test$;

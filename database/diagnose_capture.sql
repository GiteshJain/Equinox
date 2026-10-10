-- TEMPORARY (capture-data build, removed before review): the shape of the captured data on last night's copy.
-- Prints counts and descriptions with every number, route and registration masked; never amounts or rows.
select 'planner tables present: ' || (to_regclass('public.worlds') is not null)::text;
select 'raw ' || kind || ': ' || count(*) || ' pages, ' || min(captured_at)::date || ' .. ' || max(captured_at)::date
  from public.game_capture_raw group by kind order by kind;
select 'names ' || t || ': ' || string_agg(distinct airline, ', ')
  from (select 'raw' t, airline from public.game_capture_raw union all select 'stmt', airline from public.game_statement
        union all select 'loads', airline from public.game_loads union all select 'events', airline from public.game_events
        union all select 'bal', airline from public.game_balance union all select 'pnl', airline from public.game_pnl) x group by t;
select 'rows: stmt ' || (select count(*) from public.game_statement) || ', loads ' || (select count(*) from public.game_loads)
    || ', events ' || (select count(*) from public.game_events) || ', bal ' || (select count(*) from public.game_balance)
    || ', pnl ' || (select count(*) from public.game_pnl) || ', blk null ' || (select count(*) from public.game_statement where blk is null)
    || ', stmt ts ' || (select min(ts)::date || '..' || max(ts)::date from public.game_statement);
-- statement descriptions, masked
with s as (
  select regexp_replace(regexp_replace(regexp_replace(regexp_replace(descr, '\([A-Z]{3}-[A-Z]{3}\)', '(R)', 'g'),
           '\m[A-Z0-9]{1,2}-[A-Z0-9]{2,6}\M|\mN[0-9]{1,5}[A-Z]{0,2}\M', 'REG', 'g'), '[0-9]+', '#', 'g'), ' in [A-Z]{3}$', ' in APT') shape,
         blk, side from public.game_statement)
select 'descr [' || side || ' blk' || case when blk = 0 then '0' else '+' end || '] ' || shape || ' : ' || count(*)
  from s group by shape, side, blk = 0 order by count(*) desc;
-- blocks (as game_flight_pnl groups them) with no line of a flight type
with l as (
  select airline, ts, blk, descr, substring(descr from '\(([A-Z]{3}-[A-Z]{3})\)') route,
    (descr = 'Passenger transport income' or descr = 'Cargo transport income' or descr like 'Fuel%' or descr like 'On-board services%'
     or descr like 'Aircraft handling%' or descr like 'Passenger handling%' or descr like 'Cargo logistic%' or descr like 'Airport landing fee%'
     or descr like 'Air traffic control fee%' or descr like 'Maintenance of%') typed
  from public.game_statement
  where coalesce(blk, 1) > 0 and descr not ilike 'Leasing rate%' and descr not ilike 'Week-end closing%' and descr not ilike '%deposit%'
    and descr not ilike '%purchase%' and descr not ilike '%cabin%' and descr not ilike '%configuration%'),
b as (select airline, ts, blk, bool_or(typed or route is not null) flight, count(*) filter (where descr = 'Passenger transport income') pi,
        count(distinct route) nr, bool_or(descr like 'Maintenance of%') m, count(*) filter (where not typed) other_lines
      from l group by 1, 2, 3)
select 'blocks: ' || count(*) || ', not flight ' || count(*) filter (where not flight) || ' (blk>1: ' || count(*) filter (where not flight and blk > 1)
    || '), pax-income lines 0/1/2+: ' || count(*) filter (where pi = 0) || '/' || count(*) filter (where pi = 1) || '/' || count(*) filter (where pi > 1)
    || ', routes 0/1/2+: ' || count(*) filter (where nr = 0) || '/' || count(*) filter (where nr = 1) || '/' || count(*) filter (where nr > 1)
    || ', maintenance-only ' || count(*) filter (where m and pi = 0 and nr = 0) || ', with other lines ' || count(*) filter (where other_lines > 0 and flight)
  from b;
-- loads
select 'loads code = iata+number: ' || count(*) filter (where code ~ '^[A-Z0-9]{2} [1-9][0-9]{0,4}$') || ' of ' || count(*)
    || ', codes other: ' || coalesce(string_agg(distinct regexp_replace(code, '[0-9]', '#', 'g'), ' | ') filter (where code !~ '^[A-Z0-9]{2} [1-9][0-9]{0,4}$'), '-')
  from public.game_loads;
select 'loads prefixes: ' || string_agg(distinct airline || '=' || split_part(code, ' ', 1), ', ') from public.game_loads;
select 'loads dep_time ' || d || ' / arr ' || a || ' : ' || count(*)
  from (select coalesce(nullif(regexp_replace(dep_time, '[0-9]', '#', 'g'), ''), '(empty)') d, coalesce(regexp_replace(arr_time, '[0-9]', '#', 'g'), 'null') a
          from public.game_loads) x group by d, a order by 1;
select 'loads status ' || coalesce(status, 'null') || ' : ' || count(*) from public.game_loads group by status order by 1;
select 'pct ' || k || ': same ' || count(*) filter (where pct is not distinct from calc) || ', differ ' || count(*) filter (where pct is distinct from calc)
    || ' [pct null & seats>0: ' || count(*) filter (where pct is null and seats > 0) || '; seats 0: ' || count(*) filter (where seats = 0)
    || '; seats null & pct set: ' || count(*) filter (where seats is null and pct is not null) || '; pax null & seats set: ' || count(*) filter (where pax is null and seats is not null)
    || '; half: ' || count(*) filter (where seats > 0 and (100.0 * pax / seats) - floor(100.0 * pax / seats) = 0.5) || ']'
    || coalesce(' e.g. ' || string_agg(distinct pct || '~' || calc, ' ') filter (where pct is distinct from calc), '')
  from (select 'eco' k, eco pct, eco_pax pax, eco_seats seats, case when eco_seats > 0 then round(100.0 * eco_pax / eco_seats) end calc from public.game_loads
        union all select 'bus', bus, bus_pax, bus_seats, case when bus_seats > 0 then round(100.0 * bus_pax / bus_seats) end from public.game_loads
        union all select 'fst', fst, fst_pax, fst_seats, case when fst_seats > 0 then round(100.0 * fst_pax / fst_seats) end from public.game_loads
        union all select 'cargo', cargo, cargo_units, cargo_cap, case when cargo_cap > 0 then round(100.0 * cargo_units / cargo_cap) end from public.game_loads) x
 group by k order by k;
select 'scale: stmt amount ' || max(scale(amount)) || ', fares ' || (select max(greatest(scale(eco_fare), scale(bus_fare), scale(fst_fare), scale(cargo_rate))) from public.game_loads)
    || ', events ' || (select max(greatest(scale(debit), scale(credit), scale(balance))) from public.game_events)
    || ', bal ' || (select max(scale(amount)) from public.game_balance) || ', pnl ' || (select max(greatest(scale(current_p), scale(last_p), scale(total_p))) from public.game_pnl)
    || ', stmt max ' || (select max(amount) from public.game_statement) / 1e6 || 'M'
  from public.game_statement;
select 'balance rows sharing a UTC date across two capture evenings: ' || count(*)
  from (select r.airline, (r.captured_at at time zone 'UTC')::date d, count(distinct ((r.captured_at - interval '10 hours') at time zone 'UTC')::date) n
          from public.game_capture_raw r where r.kind = 'balance' group by 1, 2) x where n > 1;
select 'events event_time ' || t || ' : ' || count(*) from (select regexp_replace(event_time, '[0-9]', '#', 'g') t from public.game_events) x group by t;
select 'planner_data utc entries: ' || coalesce((select count(*) from public.planner_data, jsonb_object_keys(value -> 'utc') where key = 'DATA')::text, 'none');
select 'routes in loads without utc: ' || count(distinct origin) from public.game_loads l
 where not exists (select 1 from public.planner_data d where d.key = 'DATA' and d.value -> 'utc' ? l.origin);

-- per capture day (UTC date of capture time minus 10 hours): airlines with all five kinds
select 'capture day ' || d || ': ' || count(*) filter (where k = 5) || ' airlines with all five pages, ' || count(*) || ' with any'
  from (select airline, ((captured_at - interval '10 hours') at time zone 'UTC')::date d, count(distinct kind) filter (where kind in ('statement','events','pnl','balance','loads')) k
          from public.game_capture_raw group by 1, 2) x group by d order by d;
select 'statement lines by first-captured hour bucket vs. first raw page: before ' || count(*) filter (where s.captured_at < r.first_at - interval '1 minute')
    || ', after ' || count(*) filter (where s.captured_at >= r.first_at - interval '1 minute')
  from public.game_statement s join (select airline, min(captured_at) first_at from public.game_capture_raw where kind = 'statement' group by airline) r using (airline);
select 'loads rows captured before the first raw loads page: ' || count(*) filter (where l.captured_at < r.first_at - interval '1 minute') || ' of ' || count(*)
  from public.game_loads l join (select airline, min(captured_at) first_at from public.game_capture_raw where kind = 'loads' group by airline) r using (airline);
select 'events rows captured before the first raw events page: ' || count(*) filter (where e.captured_at < r.first_at - interval '1 minute') || ' of ' || count(*)
  from public.game_events e join (select airline, min(captured_at) first_at from public.game_capture_raw where kind = 'events' group by airline) r using (airline);

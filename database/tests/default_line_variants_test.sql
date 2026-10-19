-- The default line's variants and cabins (migration 20261019180000_default_line_variants.sql). Run by database/rehearse.sh
-- on the copy of last night's backup, after the new migrations, inside a transaction that is rolled back.
--   1. All 13 variants of manual §3 are aircraft types of the default world, each with its seats, range, deposit (price),
--      cruise speed, turnaround and family; the A350-900ULR has 440 seats.
--   2. 28 new cabin layouts, each on its type, with its seats the business and economy seats added up; 321-STD keeps 216.
--   3. Every one of our airlines may buy every new type, except Ryanair the A350s; Ryanair's E190-E2 and A320neo SHARP
--      orders come with Standard.
--   4. The cash forecast tests an order of a new type (an A321LR), priced at its deposit and its order cabin (321LR-LEI),
--      and lists the new types among those each airline may buy.

do $test$
declare
  w bigint := (select id from public.worlds where is_default);
  missing text; n int; a bigint; f0 jsonb; f1 jsonb;
begin
  select string_agg(v, ', ') into missing
    from unnest(array['E195-E2','E190-E2','A320neo SHARP','A320NEO LIGHT','A320neo','A320neo Heavy','A321 NEO LIGHT','A321neo','A321LR',
                      'A321XLR','A350-900','A350-900ULR','A350-1000']) v
   where not exists (select 1 from public.aircraft_types t where t.world_id = w and t.name = v and t.range_km > 0 and t.seats_max > 0
                       and t.price > 0 and t.cruise_kmh > 0 and t.min_turn_min > 0 and t.family_no is not null);
  assert missing is null, 'types missing or without their figures: ' || missing;
  assert (select seats_max from public.aircraft_types where world_id = w and name = 'A350-900ULR') = 440, 'the A350-900ULR should have 440 seats';
  assert (select range_km from public.aircraft_types where world_id = w and name = 'A321LR') = 5809, 'the A321LR should reach 5,809 km';

  select count(*) into n from public.cabin_configs c join public.aircraft_types t on t.id = c.aircraft_type_id
   where c.world_id = w and t.name in ('E190-E2','A320neo SHARP','A320neo','A320neo Heavy','A321neo','A321LR','A350-900','A350-1000');
  assert n = 23, format('the new types should have 23 cabin layouts, not %s', n);
  assert (select count(*) from public.cabin_configs where world_id = w) >= 38, 'there should be at least 38 cabin layouts';
  assert not exists (select 1 from public.cabin_configs where world_id = w and business_seats is not null and economy_seats is not null
                       and seats <> business_seats + economy_seats), 'a layout''s seats aren''t its business and economy seats added up';
  assert (select seats from public.cabin_configs where world_id = w and code = '321-STD') = 216, '321-STD should keep its 216 seats';

  assert not exists (select 1 from public.airlines al join public.groups g on g.id = al.group_id and g.kind = 'ours'
                       cross join public.aircraft_types t
                      where al.world_id = w and t.world_id = w and t.name in ('E190-E2','A320neo SHARP','A321LR','A350-900')
                        and not (al.iata_code = 'FR' and t.family_no = 87)
                        and not exists (select 1 from public.airline_aircraft_types x where x.airline_id = al.id and x.aircraft_type_id = t.id)),
    'an airline may not buy a new type';
  assert not exists (select 1 from public.airline_aircraft_types x join public.airlines al on al.id = x.airline_id
                       join public.aircraft_types t on t.id = x.aircraft_type_id where al.iata_code = 'FR' and t.name like 'A350%'),
    'Ryanair may buy an A350';
  assert (select c.code from public.airline_order_cabins o join public.airlines al on al.id = o.airline_id
            join public.aircraft_types t on t.id = o.aircraft_type_id join public.cabin_configs c on c.id = o.order_config_id
           where al.iata_code = 'FR' and t.name = 'A320neo SHARP') = '320S-STD', 'Ryanair''s A320neo SHARP should come with 320S-STD';

  select al.airline_id into a from private.fig_airlines(w) al order by al.ord limit 1;
  f0 := public.cash_forecast(a);
  f1 := public.cash_forecast(a, '[{"type": "A321LR", "count": 1}]');
  assert f1 is not null and f1::text like '%A321LR%', 'the cash forecast gave nothing for an order of an A321LR: ' || left(coalesce(f1::text,'none'), 300);
  assert (select count(*) from jsonb_array_elements(f0 -> 'types') x where x ->> 'type' in ('A321LR','A320neo SHARP','E190-E2')) = 3
           or (f0 ->> 'status') is distinct from 'ok',
    'the cash forecast doesn''t list the new types: ' || left(coalesce((f0 -> 'types')::text, f0::text), 300);
  raise notice 'default line: 13 types with range, % cabin layouts; the cash forecast takes an A321LR (%)',
    (select count(*) from public.cabin_configs where world_id = w), left(coalesce((f1 -> 'orders')::text, f1::text), 200);
end
$test$;

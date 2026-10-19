-- The default line's variants and their cabins (19 Oct; manual §3, decided 18 Oct; spec docs/specs/2026-10-19-default-line-variants.md).
-- Figures from Gitesh's sheet of the game's aircraft pages (Default Line Variants, 19 Oct): each variant's seats, range
-- with a full load, deposit (what an order costs up front, aircraft_types.price) and cruise speed. The game shows no
-- turnaround, so each new variant takes its family's (A320 family 66 minutes, E-jet E2 67, A350 90), with its family's
-- maintenance figures. aircraft_types.range_km is new: the range with a full load. The five types we had take the sheet's
-- figures too (deposits to the thousand, cruise speeds, and the A350-900ULR's 440 seats). Every airline may buy every new
-- type (airline_aircraft_types; Ryanair no A350, manual §3), so the cash forecast tests them. 28 new cabin layouts, and
-- the seat split on the existing ones, from the sheet's cabin tab; an order's cabin for the cash forecast is the
-- narrowbodies' Leisure layout and the A350s' Comfort, as for the types we had, and Ryanair's Standard where it has one.
select set_config('equinox.actor', 'claude', true), set_config('equinox.actor_detail', 'building: default line variants', true);

alter table public.aircraft_types add column range_km integer;
comment on column public.aircraft_types.range_km is 'Range with a full load, km, from the game''s aircraft page (manual §3, the default line)';

-- the types and their figures; a new type takes its family's turnaround, maintenance and ground figures
with w as (select id from public.worlds where is_default), v(name, seats, range_km, price, cruise, fam) as (values
  ('E195-E2', 146, 3542, 1771000, 830, 'E-jet E2'),
  ('E190-E2', 114, 4065, 1683000, 830, 'E-jet E2'),
  ('A320neo SHARP', 189, 3355, 2058000, 840, 'A320 family'),
  ('A320NEO LIGHT', 189, 3690, 2145000, 840, 'A320 family'),
  ('A320neo', 189, 4045, 2170000, 840, 'A320 family'),
  ('A320neo Heavy', 189, 4708, 2241000, 840, 'A320 family'),
  ('A321 NEO LIGHT', 240, 4192, 2401000, 840, 'A320 family'),
  ('A321neo', 240, 4742, 2532000, 840, 'A320 family'),
  ('A321LR', 240, 5809, 2711000, 840, 'A320 family'),
  ('A321XLR', 240, 6939, 2862000, 840, 'A320 family'),
  ('A350-900', 440, 11102, 7005000, 910, 'A350'),
  ('A350-900ULR', 440, 11690, 7193000, 910, 'A350'),
  ('A350-1000', 480, 11102, 7854000, 910, 'A350')),
f(fam, family_no, turn, gap, mph, mpc, keep) as (values ('E-jet E2', 83, 67, 3.0, 1.80, 22.00, 72), ('A320 family', 9, 66, 4.0, 1.70, 27.60, 72),
                                                  ('A350', 87, 90, 4.0, 2.00, 37.00, 97)),
upd as (update public.aircraft_types t set seats_max = v.seats, range_km = v.range_km, price = v.price, cruise_kmh = v.cruise
          from v, w where t.world_id = w.id and t.name = v.name returning t.name)
insert into public.aircraft_types (world_id, name, family_no, seats_max, cruise_kmh, min_turn_min, gap_target_h, maint_per_hour, maint_per_cycle,
                                   ground_keep_min, price, range_km)
select w.id, v.name, f.family_no, v.seats, v.cruise, f.turn, f.gap, f.mph, f.mpc, f.keep, v.price, v.range_km
  from v join f on f.fam = v.fam cross join w
 where not exists (select 1 from public.aircraft_types t where t.world_id = w.id and t.name = v.name);

-- the cabin layouts: new ones added, the seat split filled in on the ones we had (321-STD keeps its 216 seats: the sheet's 180 economy doesn't add up to them, so its split waits for a check)
with w as (select id from public.worlds where is_default), c(code, type, cabin, bus, eco, cost, note) as (values
  ('E195-LEI', 'E195-E2', 'Leisure', 12, 100, 97000, '12 Recliner Longhaul business + 100 Leisure economy'),
  ('E195-LP', 'E195-E2', 'Leisure Plus', 12, 96, 103800, '12 Recliner Longhaul business + 96 Leisure Plus economy'),
  ('E195-CMF', 'E195-E2', 'Comfort', 12, 72, 99000, '12 Recliner Longhaul business + 72 Comfort economy'),
  ('E195-STD', 'E195-E2', 'Standard', 0, 124, 62000, '124 Standard economy'),
  ('E190-LEI', 'E190-E2', 'Leisure', 9, 80, 76250, '9 Recliner Longhaul business + 80 Leisure economy'),
  ('E190-LP', 'E190-E2', 'Leisure Plus', 9, 80, 84250, '9 Recliner Longhaul business + 80 Leisure Plus economy'),
  ('E190-CMF', 'E190-E2', 'Comfort', 9, 60, 80250, '9 Recliner Longhaul business + 60 Comfort economy'),
  ('E190-STD', 'E190-E2', 'Standard', 0, 104, 52000, '104 Standard economy'),
  ('320S-LEI', 'A320neo SHARP', 'Leisure', 15, 138, 162600, '15 Lie-Flat 140 business + 138 Leisure economy'),
  ('320S-LP', 'A320neo SHARP', 'Leisure Plus', 15, 132, 171600, '15 Lie-Flat 140 business + 132 Leisure Plus economy'),
  ('320S-CMF', 'A320neo SHARP', 'Comfort', 15, 110, 176000, '15 Lie-Flat 140 business + 110 Comfort economy'),
  ('320S-STD', 'A320neo SHARP', 'Standard', 0, 180, 90000, '180 Standard economy'),
  ('320-LEI', 'A320NEO LIGHT', 'Leisure', 15, 138, 162600, '15 Lie-Flat 140 business + 138 Leisure economy'),
  ('320-LP', 'A320NEO LIGHT', 'Leisure Plus', 15, 132, 171600, '15 Lie-Flat 140 business + 132 Leisure Plus economy'),
  ('320-CMF', 'A320NEO LIGHT', 'Comfort', 15, 110, 176000, '15 Lie-Flat 140 business + 110 Comfort economy'),
  ('320N-LEI', 'A320neo', 'Leisure', 15, 138, 162600, '15 Lie-Flat 140 business + 138 Leisure economy'),
  ('320N-LP', 'A320neo', 'Leisure Plus', 15, 132, 171600, '15 Lie-Flat 140 business + 132 Leisure Plus economy'),
  ('320N-CMF', 'A320neo', 'Comfort', 15, 110, 176000, '15 Lie-Flat 140 business + 110 Comfort economy'),
  ('320H-LEI', 'A320neo Heavy', 'Leisure', 15, 138, 162600, '15 Lie-Flat 140 business + 138 Leisure economy'),
  ('320H-LP', 'A320neo Heavy', 'Leisure Plus', 15, 132, 171600, '15 Lie-Flat 140 business + 132 Leisure Plus economy'),
  ('320H-CMF', 'A320neo Heavy', 'Comfort', 15, 110, 176000, '15 Lie-Flat 140 business + 110 Comfort economy'),
  ('321-LEI', 'A321 NEO LIGHT', 'Leisure', 15, 180, 192000, '15 Lie-Flat 140 business + 180 Leisure economy'),
  ('321-LEI OLD', 'A321 NEO LIGHT', 'Leisure', 16, 156, 195600, '16 Full Bed business + 156 Leisure economy; none left in service'),
  ('321-LP', 'A321 NEO LIGHT', 'Leisure Plus', 16, 150, 206400, '16 Full Bed business + 150 Leisure Plus economy'),
  ('321-CMF', 'A321 NEO LIGHT', 'Comfort', 16, 125, 211400, '16 Full Bed business + 125 Comfort economy'),
  ('321-STD', 'A321 NEO LIGHT', 'Standard', 0, 180, 108000, '180 Standard economy'),
  ('321N-LEI', 'A321neo', 'Leisure', 15, 180, 192000, '15 Lie-Flat 140 business + 180 Leisure economy'),
  ('321N-LP', 'A321neo', 'Leisure Plus', 16, 150, 206400, '16 Full Bed business + 150 Leisure Plus economy'),
  ('321N-CMF', 'A321neo', 'Comfort', 16, 125, 211400, '16 Full Bed business + 125 Comfort economy'),
  ('321LR-LEI', 'A321LR', 'Leisure', 15, 180, 192000, '15 Lie-Flat 140 business + 180 Leisure economy'),
  ('321LR-LP', 'A321LR', 'Leisure Plus', 16, 150, 206400, '16 Full Bed business + 150 Leisure Plus economy'),
  ('321LR-CMF', 'A321LR', 'Comfort', 16, 125, 211400, '16 Full Bed business + 125 Comfort economy'),
  ('XLR-LP', 'A321XLR', 'Leisure Plus', 16, 150, 206400, '16 Full Bed business + 150 Leisure Plus economy'),
  ('XLR-CMF', 'A321XLR', 'Comfort', 16, 125, 211400, '16 Full Bed business + 125 Comfort economy'),
  ('359-LP', 'A350-900', 'Leisure Plus', 25, 306, 387300, '25 Full Bed Wid business + 306 Leisure Plus economy; business seat name to check (cut off in the sheet''s screenshot)'),
  ('359-CMF', 'A350-900', 'Comfort', 24, 264, 431280, '24 Open Suite Deluxe business + 264 Comfort economy'),
  ('350-CMF', 'A350-900ULR', 'Comfort', 24, 264, 431280, '24 Open Suite Deluxe business + 264 Comfort economy'),
  ('35K-CMF', 'A350-1000', 'Comfort', 28, 272, 467160, '28 Open Suite Deluxe business + 272 Comfort economy')),
ct as (select c.*, t.id as type_id, w.id as world_id from c cross join w join public.aircraft_types t on t.world_id = w.id and t.name = c.type),
upd as (update public.cabin_configs x set business_seats = ct.bus, economy_seats = ct.eco,
               note = coalesce(x.note, ct.note)
          from ct where x.world_id = ct.world_id and x.code = ct.code and x.code <> '321-STD'
            and (x.seats is null or ct.bus is null or ct.eco is null or x.seats = ct.bus + ct.eco) returning x.code)
insert into public.cabin_configs (world_id, code, aircraft_type_id, cabin, seats, business_seats, economy_seats, cost, note)
select ct.world_id, ct.code, ct.type_id, ct.cabin, ct.bus + ct.eco, ct.bus, ct.eco, ct.cost, ct.note
  from ct where not exists (select 1 from public.cabin_configs x where x.world_id = ct.world_id and x.code = ct.code);

-- an order's cabin for the cash forecast: Leisure on the new narrowbodies, Comfort on the A350s (as for the types we had)
update public.aircraft_types t set order_config_id = cc.id
  from (values ('E190-E2', 'E190-LEI'), ('A320neo SHARP', '320S-LEI'), ('A320neo', '320N-LEI'), ('A320neo Heavy', '320H-LEI'),
               ('A321neo', '321N-LEI'), ('A321LR', '321LR-LEI'), ('A350-900', '359-CMF'), ('A350-1000', '35K-CMF')) as o(type, code)
  join public.cabin_configs cc on cc.code = o.code and cc.world_id = (select id from public.worlds where is_default)
 where t.world_id = cc.world_id and t.name = o.type and t.order_config_id is null;

-- every airline may buy every new type; Ryanair no A350 (manual §3)
insert into public.airline_aircraft_types (world_id, airline_id, aircraft_type_id)
select a.world_id, a.id, t.id
  from public.airlines a join public.groups g on g.id = a.group_id and g.kind = 'ours'
  join public.aircraft_types t on t.world_id = a.world_id
 where a.world_id = (select id from public.worlds where is_default)
   and t.name in ('E190-E2', 'A320neo SHARP', 'A320neo', 'A320neo Heavy', 'A321neo', 'A321LR', 'A350-900', 'A350-1000')
   and not (a.iata_code = 'FR' and t.family_no = 87)
   and not exists (select 1 from public.airline_aircraft_types x where x.airline_id = a.id and x.aircraft_type_id = t.id);

-- Ryanair's own order cabin where it has a Standard layout
insert into public.airline_order_cabins (world_id, airline_id, aircraft_type_id, order_config_id)
select a.world_id, a.id, t.id, cc.id
  from (values ('E190-E2', 'E190-STD'), ('A320neo SHARP', '320S-STD')) as o(type, code)
  join public.airlines a on a.iata_code = 'FR' and a.world_id = (select id from public.worlds where is_default)
  join public.aircraft_types t on t.world_id = a.world_id and t.name = o.type
  join public.cabin_configs cc on cc.world_id = a.world_id and cc.code = o.code
 where not exists (select 1 from public.airline_order_cabins x where x.airline_id = a.id and x.aircraft_type_id = t.id);

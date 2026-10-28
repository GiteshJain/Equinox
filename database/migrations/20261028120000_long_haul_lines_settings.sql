-- Long haul in 7-day lines: the settings (28 Oct 2026; spec docs/specs/2026-10-27-long-haul-lines.md, "Settings"; brief
-- docs/briefs/2026-10-27-long-haul-lines.md, option B; manual §4, under Decided, not yet built until the last pull
-- request of the build merges). Build pull request 1 of 4: the planning library's line optimiser, the maintenance
-- spacing on every card and the card check across a line.
--
-- Why (Gitesh, 27 Oct): routes whose round trip doesn't fit in a day, those beyond about 7,750 km, fly in 7-day
-- rotating lines of 7 aircraft of one type at one airline, each a day apart. And condition can fall below 50% with
-- only one long maintenance stop a week, so the stops that count must be no more than 40 hours apart.
--
-- Adds three settings rows, world-level in every world (airline null) as the other settings migrations do, described, and changes, drops and renames nothing, so
-- it can be applied from the chat. Each reaches the planning library through rules_input(), which carries every world
-- setting as it is (no function changes):
--   line_min_km 7,750: routes at or beyond this go on lines. The Scheduling chat's choice of which routes; nothing
--     enforces it automatically.
--   maintenance_max_gap_h 40: the longest stretch between two stops that count for maintenance (the stop rule as in
--     lib/rules/src/maintenance.ts: at least maint_min_ground_min beyond the type's ground_keep_min). The library reports
--     it on every card's maintenance figures (max_gap_h, max_gap_ok), and check-card and the Tails issues flag a
--     stretch over it ("no maintenance stop for 78 h, over 40"); the line optimiser refuses a line with one. An input
--     without the row isn't checked.
--   line_aircraft 7: aircraft on a line (the game repeats each aircraft's week, so a rotating line is exactly 7 days
--     and 7 aircraft). Read by nothing yet: the planner's lines (build pull request 2) and the pool progress (4) will.

select set_config('equinox.actor', 'migration', true),
       set_config('equinox.actor_detail', '20261028120000_long_haul_lines_settings', true);

insert into public.settings (world_id, airline_id, key, value, unit, description, since, reason)
select w.id, null, s.key, s.value, s.unit, s.description, date '2026-10-28', s.reason
  from public.worlds w
 cross join (values
   ('line_min_km', '7750'::jsonb, 'km',
    'Long haul in 7-day lines (manual §4, decided 27 Oct): routes at or beyond this distance, whose round trip with turns and a maintenance stop doesn''t fit in a day, are planned as 7-day rotating lines (line_aircraft aircraft of one type at one airline, each a day apart, so every route on the line flies daily at the same time). The Scheduling chat''s choice of which routes; nothing enforces it automatically. Shorter routes keep the 24-hour day.',
    'Gitesh, 27 Oct: option B of the brief docs/briefs/2026-10-27-long-haul-lines.md; up to about 7,750 km a 24-hour day is 90–99% used, beyond it one aircraft can''t fly a route daily'),
   ('maintenance_max_gap_h', '40'::jsonb, 'hours',
    'The longest stretch an aircraft may fly between two ground stops that count for maintenance (a stop counts when its ground time is at least maint_min_ground_min beyond the type''s ground_keep_min, the planning library''s maintenance rule), measured from the departure after one stop to the landing at the next over the aircraft''s repeating week, wrapping around the week''s end. The library''s maintenance figures give it for every card and aircraft (max_gap_h, max_gap_ok); check-card and the Tails issues flag a stretch over it, and the line optimiser refuses a line with one. Beside maintenance_min_pct, which judges the week''s total.',
    'Gitesh, 27 Oct: condition can fall below 50% with only one long maintenance stop a week (the first hand-built A350 line had a 78-hour stretch); spec docs/specs/2026-10-27-long-haul-lines.md'),
   ('line_aircraft', '7'::jsonb, 'aircraft',
    'Aircraft on a 7-day rotating line (manual §4): the game repeats each aircraft''s week, so a line is exactly 7 days flown by 7 aircraft, each a day apart (aircraft k flies line day d on weekday ((d + k − 2) mod 7) + 1). The planner''s lines and the pool progress on Today → Orders ("XLR line, Pan Am: 3 of 7 ordered") count against it.',
    'Gitesh, 27 Oct: spec docs/specs/2026-10-27-long-haul-lines.md, "How a line works"')
 ) as s(key, value, unit, description, reason)
on conflict on constraint settings_world_airline_key_key do nothing;

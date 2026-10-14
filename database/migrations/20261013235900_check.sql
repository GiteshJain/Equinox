-- The new planner's Check screen (decision #18, build pull request 9). Spec: docs/specs/2026-10-13-check.md ("anything the
-- old screen works out that has no home yet goes to the library (with cases) or the database's figures ... add only";
-- design §2: one source for rule numbers, nothing typed into code).
--
-- Adds seven settings, in every world, numbers the old Check kept in its code and the planning library now reads through
-- rules_input() (which carries every setting); changes and takes away nothing, so it can be applied from the chat:
--   cabin_refit_cost (200000 AS$): a cabin refit's cost (the old REFIT_M, 0.2M; manual §5), logged as a loss when Check's
--     "Refitted to" is used, and named in the Cabins board's note;
--   cabin_refit_share_pct (70): Cabins marks an aircraft flying at least this share of its block time in markets that
--     want another cabin, the refits that pay (the old cabinsBoard's 70%);
--   growth_big_min_stars (4): a route with at least this many stars is a big market for the order rotation, one with
--     fewer a smaller feeder (the old moveCandidates);
--   growth_ready_min_days (5) and growth_ready_full_share (0.95): a route is ready for another flight from the load
--     reports when this share of its departures were at 95%+ over at least this many reported days (the old
--     moveCandidates' frequency move, and growthBoard's list when no profit was captured);
--   order_queue_grace_h (6) and order_queue_warn_h (48): an order queue counts a delivery until this many hours after it
--     arrives, and flags a queue that runs dry within this many hours (the old growthBoard's order queues).

select set_config('equinox.actor', 'migration', true),
       set_config('equinox.actor_detail', '20261013235900_check', true);

insert into public.settings (world_id, airline_id, key, value, unit, description, since, reason)
select w.id, null, s.key, s.value, s.unit, s.description, date '2026-10-13', s.reason
  from public.worlds w
 cross join (values
   ('cabin_refit_cost', '200000'::jsonb, 'AS$',
    'A cabin refit''s cost: Check → Cabins logs it as a loss on the day a refit is logged (the old planner''s REFIT_M); manual §5',
    'The old planner''s 0.2M refit, given a home of its own (#19)'),
   ('cabin_refit_share_pct', '70'::jsonb, 'percent of block time',
    'Check → Cabins marks an aircraft flying at least this share of its block time in markets that want another cabin: the refits that pay (the old cabinsBoard)',
    'The old planner''s 70%, given a home of its own (#19)'),
   ('growth_big_min_stars', '4'::jsonb, 'stars',
    'The order rotation (manual §3): a route with at least this many stars is a big market, one with fewer a smaller feeder (the old moveCandidates)',
    'The old planner''s 4 stars, given a home of its own (#19)'),
   ('growth_ready_min_days', '5'::jsonb, 'reported days',
    'Check → Growth: a route is ready for another flight from the load reports after at least this many reported days at growth_ready_full_share (the old moveCandidates and growthBoard)',
    'The old planner''s 5 days, given a home of its own (#19)'),
   ('growth_ready_full_share', '0.95'::jsonb, 'share of departures',
    'Check → Growth: the share of a route''s departures at 95%+ over growth_ready_min_days that makes it ready for another flight from the load reports (the old moveCandidates and growthBoard)',
    'The old planner''s 95%, given a home of its own (#19)'),
   ('order_queue_grace_h', '6'::jsonb, 'hours',
    'Check → Growth''s order queues count a delivery until this many hours after it arrives (the old growthBoard)',
    'The old planner''s 6 hours, given a home of its own (#19)'),
   ('order_queue_warn_h', '48'::jsonb, 'hours',
    'Check → Growth''s order queues flag a queue that runs dry within this many hours (the old growthBoard)',
    'The old planner''s 48 hours, given a home of its own (#19)')
 ) as s(key, value, unit, description, reason)
on conflict on constraint settings_world_airline_key_key do nothing;

select set_config('equinox.actor', '', true), set_config('equinox.actor_detail', '', true);

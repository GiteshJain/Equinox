-- The captured figures plan each call afresh (24 Oct). A plpgsql function keeps its queries' plans on the connection,
-- and after five runs Postgres may switch to one generic plan for every later call. The data API's pooled connections
-- serve hundreds of calls each, so the figures ended up on generic plans. Measured on live on 24 Oct, fare_ladder for
-- Kingfisher on one connection ran about 1.2 s for its first five calls, then 4.6 and 4.1 s, against a steady 1.1 s with
-- plan_cache_mode = force_custom_plan. A few of them at once went past their 30 s limit, and the planner showed
-- "Couldn't read the fare ladder: canceling statement due to statement timeout". A setting on a function holds for
-- everything it calls, so the setting on these sixteen (the functions with their own 30 s limit) reaches their builders
-- in private. Planning each call afresh costs milliseconds.
select set_config('equinox.actor', 'claude', true), set_config('equinox.actor_detail', 'building: figures custom plans', true);

alter function public.airline_cards(bigint, timestamptz) set plan_cache_mode = 'force_custom_plan';
alter function public.airline_profit(bigint, timestamptz) set plan_cache_mode = 'force_custom_plan';
alter function public.cash_forecast(bigint, jsonb, timestamptz) set plan_cache_mode = 'force_custom_plan';
alter function public.route_profit(bigint, integer, timestamptz) set plan_cache_mode = 'force_custom_plan';
alter function public.aircraft_profit(bigint, integer, timestamptz) set plan_cache_mode = 'force_custom_plan';
alter function public.fare_changes(bigint, timestamptz) set plan_cache_mode = 'force_custom_plan';
alter function public.fare_plan_status(bigint, timestamptz) set plan_cache_mode = 'force_custom_plan';
alter function public.fare_ladder(bigint, timestamptz) set plan_cache_mode = 'force_custom_plan';
alter function public.growth_signals(bigint, timestamptz) set plan_cache_mode = 'force_custom_plan';
alter function public.hub_progress(bigint, timestamptz) set plan_cache_mode = 'force_custom_plan';
alter function public.route_loads(bigint, timestamptz) set plan_cache_mode = 'force_custom_plan';
alter function public.route_story(bigint, timestamptz) set plan_cache_mode = 'force_custom_plan';
alter function public.competition(bigint, timestamptz, integer) set plan_cache_mode = 'force_custom_plan';
alter function public.fleet_checks(bigint, timestamptz) set plan_cache_mode = 'force_custom_plan';
alter function public.export_for_report(text, text, text) set plan_cache_mode = 'force_custom_plan';
alter function public.capture_fare_actions(text) set plan_cache_mode = 'force_custom_plan';

-- The planner's figures get time to finish when many are read at once (22 Oct; spec
-- docs/specs/2026-10-22-performance-load.md). Performance asks for about 20 captured figures on opening (six
-- airlines' profit, cash forecast and fare ladder, the cards, growth signals, hub progress). Each takes about half a
-- second alone, but run together on the small database they slowed to 2 to 8 seconds, and some crossed staff's 8
-- second limit ("canceling statement due to statement timeout"). This gives each of these figure functions its own
-- 30 second limit, as export_for_report has since 17 Oct (20261017170000_figures_timeout.sql). The data API applies a
-- function's own statement_timeout to the call's transaction, so only these functions get the longer limit; every
-- other call keeps the role's (anon 3 s, staff 8 s). All of them still check that the caller is staff.
select set_config('equinox.actor', 'claude', true), set_config('equinox.actor_detail', 'building: performance load', true);

alter function public.airline_cards(bigint, timestamptz) set statement_timeout = '30s';
alter function public.airline_profit(bigint, timestamptz) set statement_timeout = '30s';
alter function public.cash_forecast(bigint, jsonb, timestamptz) set statement_timeout = '30s';
alter function public.route_profit(bigint, integer, timestamptz) set statement_timeout = '30s';
alter function public.aircraft_profit(bigint, integer, timestamptz) set statement_timeout = '30s';
alter function public.fare_changes(bigint, timestamptz) set statement_timeout = '30s';
alter function public.fare_plan_status(bigint, timestamptz) set statement_timeout = '30s';
alter function public.fare_ladder(bigint, timestamptz) set statement_timeout = '30s';
alter function public.growth_signals(bigint, timestamptz) set statement_timeout = '30s';
alter function public.hub_progress(bigint, timestamptz) set statement_timeout = '30s';
alter function public.route_loads(bigint, timestamptz) set statement_timeout = '30s';
alter function public.route_story(bigint, timestamptz) set statement_timeout = '30s';

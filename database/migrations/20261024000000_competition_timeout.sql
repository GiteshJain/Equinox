-- competition() gets its own 30 second limit, as the other captured figures have since 22 Oct
-- (20261022050000_figures_timeout_staff.sql). Since 23 Oct Home reads each airline's competition() on opening (the
-- rival moves in needs attention's cards), six calls at once beside route_loads, fleet_checks and rules_input. Each
-- takes about 1.2 seconds alone, but together on the small database staff's calls averaged 3.6 seconds and the
-- slowest crossed staff's 8 second limit: on 24 Oct from 00:02 UTC Home showed "Couldn't read the competition
-- analysis: canceling statement due to statement timeout" in bursts of six. competition() came on 21 Oct, the day
-- before the other figures got their limit, and was left out. The data API applies a function's own
-- statement_timeout to the call's transaction, so only this function gets the longer limit; it still checks that the
-- caller is staff.
select set_config('equinox.actor', 'claude', true), set_config('equinox.actor_detail', 'building: competition timeout', true);

alter function public.competition(bigint, timestamptz, integer) set statement_timeout = '30s';

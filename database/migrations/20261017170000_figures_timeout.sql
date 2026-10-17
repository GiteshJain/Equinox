-- The report's figures get time to finish (17 Oct; spec docs/specs/2026-10-17-figures-timeout.md).
-- export_for_report('figures') works out every captured figure for every airline in one call: about 3.2 seconds on
-- 17 Oct. The scripts call it signed out (anon), whose statement limit is 3 seconds, so it failed twice that morning
-- (error 57014, cut off at 3.09 s) before a third try got through. This gives export_for_report its own limit of
-- 30 seconds. The data API (PostgREST 12 and later) applies a function's own statement_timeout to the call's
-- transaction, so only this function gets the longer limit; every other call keeps the role's (anon 3 s, staff 8 s).
-- Calling it still needs the ingest secret.
select set_config('equinox.actor', 'claude', true), set_config('equinox.actor_detail', 'building: figures timeout', true);

alter function public.export_for_report(text, text, text) set statement_timeout = '30s';

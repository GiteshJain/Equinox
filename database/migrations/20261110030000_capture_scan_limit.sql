-- capture_scan() gets its own 30-second statement limit (10 Nov 2026, Building chat; the map's "When something breaks":
-- a call that keeps running past its role's limit gets its own, as capture_ingest() and capture_market() have).
--
-- Why: the evening capture calls capture_scan() signed out, so it ran under the anon role's 3 seconds. A scan's finish
-- builds the airport summaries, works out the rivals' connections on our pairs (private.scan_connections(), 2.7 s on its
-- own on 10 Nov, with 2,623 of our pairs) and keeps the week's pairs. Since 4 Nov the connections step has timed out at
-- every finish but one (4, 9 and 10 Nov: "connections not worked out: canceling statement due to statement timeout"),
-- so Competition, the route page and the weekly report showed rivals' connecting departures from 3 Nov. The three scans
-- were worked out by hand on 10 Nov. 30 s stays under the API's 60 s cut-off. Each call is planned afresh, as every
-- function with its own limit is (24 Oct).
--
-- Changes two settings on one function and adds a sentence to its description; nothing else.

alter function public.capture_scan(text, text, jsonb) set statement_timeout = '30s';
alter function public.capture_scan(text, text, jsonb) set plan_cache_mode = 'force_custom_plan';

do $describe$
declare d text := obj_description('public.capture_scan(text, text, jsonb)'::regprocedure, 'pg_proc');
begin
  if position('own 30-second limit' in coalesce(d, '')) = 0 then
    execute format('comment on function public.capture_scan(text, text, jsonb) is %L', coalesce(d, '')
      || ' Since 10 Nov it has its own 30-second limit (signed out, a call otherwise has the anon role''s short one): from 4 Nov the finish''s rival connections timed out under it.');
  end if;
end
$describe$;

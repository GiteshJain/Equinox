-- capture_ingest() gets its own 30-second statement limit (9 Nov 2026, Building chat; the map's "When something breaks":
-- a call that keeps running past its role's limit gets its own, as export_for_report() has).
--
-- Why: on 9 Nov (03:01 UTC) Ryanair's bank statement page came back 500, "canceling statement due to statement timeout".
-- The capture calls capture_ingest() signed out, so it ran under the anon role's short limit. No capture had run on 6, 7
-- or 8 Nov, so all 1,500 lines of the statement were new and had to be folded into flights at once; on a normal evening
-- most are stored already and the call is quick. The page was lost, so the evening's day wasn't complete and the world
-- scan and market pages didn't run. 30 s stays under the API's 60 s cut-off. Each call is planned afresh, as every
-- function with its own limit is (24 Oct).
--
-- Changes two settings on one function and adds a sentence to its description; nothing else.

alter function public.capture_ingest(text, text, text, text, jsonb) set statement_timeout = '30s';
alter function public.capture_ingest(text, text, text, text, jsonb) set plan_cache_mode = 'force_custom_plan';

do $describe$
declare d text := obj_description('public.capture_ingest(text, text, text, text, jsonb)'::regprocedure, 'pg_proc');
begin
  if position('own 30-second limit' in coalesce(d, '')) = 0 then
    execute format('comment on function public.capture_ingest(text, text, text, text, jsonb) is %L', coalesce(d, '')
      || ' Since 9 Nov it has its own 30-second limit (signed out, a call otherwise has the anon role''s short one): a bank statement of 1,500 new lines, after evenings without a capture, timed out on 9 Nov.');
  end if;
end
$describe$;

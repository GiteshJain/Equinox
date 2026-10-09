-- Loads: a save can no longer overwrite captured days (found while writing the #13 brief, fixed 9 Oct 2026).
--
-- Before: the capture added days to a month's loads document without updating its saved time, so a browser that had
-- saved that month itself kept its own older copy; its next save rewrote the whole month from that copy and could wipe
-- captured days.
-- After:
--   1. apply_loads_from_capture() sets saved_at, so browsers pick up captured days.
--   2. The planner saves through save_loads(), which merges only the days and flights it changed into the month,
--      inside the database, with the month's row locked.
--   3. Browsers can no longer write planner_loads directly (the insert and update rules are removed), so an old open
--      tab can't overwrite a month either. The capture and save_loads() run as owner and check permission themselves.

create or replace function public.apply_loads_from_capture(p_airline text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare d record; mon text; cur jsonb; day jsonb; f jsonb; n int := 0; alnames int;
  ms bigint := (extract(epoch from clock_timestamp()) * 1000)::bigint;
begin
  for d in select distinct flight_date from public.game_loads where airline = p_airline and flight_date >= current_date - 3 loop
    mon := to_char(d.flight_date, 'YYYY-MM');
    select json::jsonb into cur from public.planner_loads where month = mon for update; cur := coalesce(cur, '{}'::jsonb);
    day := coalesce(cur->(d.flight_date::text), '{}'::jsonb);
    f := coalesce(day->'f', '{}'::jsonb);
    -- economy load per flight, keyed the way the planner keys its reports: "Airline|flight number"
    select coalesce(jsonb_object_agg(airline||'|'||regexp_replace(code, '^[A-Z0-9]+\s*', ''), eco), '{}'::jsonb) into f
      from (select airline, code, eco from public.game_loads where airline = p_airline and flight_date = d.flight_date and eco is not null) q;
    day := jsonb_set(day, '{f}', coalesce(day->'f', '{}'::jsonb) || f, true);
    select count(distinct airline) into alnames from public.game_loads where flight_date = d.flight_date;
    day := day || jsonb_build_object('done', alnames >= 6, 'captured', now(), 'source', 'capture');
    cur := jsonb_set(cur, array[d.flight_date::text], day, true);
    -- saved_at moves on, so a browser holding an older copy of the month takes this one when it next loads
    insert into public.planner_loads(month, json, saved_at) values (mon, cur::text, ms)
      on conflict (month) do update set json = excluded.json, saved_at = excluded.saved_at;
    n := n + 1;
  end loop;
  return jsonb_build_object('days', n);
end $function$;

comment on function public.apply_loads_from_capture(text) is 'Copies the last 3 days of captured loads for one airline into planner_loads and moves the month''s saved_at on, so browsers pick them up. Called by capture_ingest() after each loads page.';

create or replace function public.save_loads(p_month text, p_days jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare cur jsonb; d text; p jsonb; day jsonb; f jsonb;
  ms bigint := (extract(epoch from clock_timestamp()) * 1000)::bigint;
begin
  if not public.is_planner_user() then raise exception 'only planner staff can save loads' using errcode = '42501'; end if;
  if p_month is null or p_month !~ '^\d{4}-\d{2}$' then raise exception 'month must be YYYY-MM, got %', p_month; end if;
  if jsonb_typeof(p_days) is distinct from 'object' then raise exception 'days must be an object keyed by date'; end if;
  insert into public.planner_loads(month, json, saved_at) values (p_month, '{}', 0) on conflict (month) do nothing;
  select json::jsonb into cur from public.planner_loads where month = p_month for update;
  cur := coalesce(cur, '{}'::jsonb) - '__savedAt';   -- a browser-only marker that older saves wrote into the document
  for d, p in select key, value from jsonb_each(p_days) loop
    if d !~ ('^' || p_month || '-\d{2}$') then raise exception 'day % is not in month %', d, p_month; end if;
    if jsonb_typeof(p) is distinct from 'object' then raise exception 'day % must be an object', d; end if;
    day := coalesce(cur->d, '{"done": false, "f": {}}'::jsonb);
    if p ? 'f' then
      f := coalesce(p->'f', '{}'::jsonb);                                         -- the whole day's entry, as typed
    else
      f := (coalesce(day->'f', '{}'::jsonb) || coalesce(p->'set', '{}'::jsonb))   -- single flights: set these ...
           - array(select jsonb_array_elements_text(coalesce(p->'del', '[]'::jsonb)));   -- ... and clear these
    end if;
    day := jsonb_set(day, '{f}', f, true);
    if p ? 'done' then day := day || jsonb_build_object('done', p->'done'); end if;
    if p ? 'savedAt' then day := day || jsonb_build_object('savedAt', p->'savedAt'); end if;
    cur := jsonb_set(cur, array[d], day, true);
  end loop;
  update public.planner_loads set json = cur::text, saved_at = ms where month = p_month;
  return jsonb_build_object('month', p_month, 'json', cur, 'saved_at', ms);
end $function$;

comment on function public.save_loads(text, jsonb) is 'The planner''s only way to save loads: merges the days it changed into one month of planner_loads (a day''s whole entry, or single flights set and cleared), leaves every other day as it is, and returns the merged month. Planner staff only.';

revoke all on function public.save_loads(text, jsonb) from public, anon;
grant execute on function public.save_loads(text, jsonb) to authenticated;

drop policy if exists "planner users insert loads" on public.planner_loads;
drop policy if exists "planner users update loads" on public.planner_loads;

comment on table public.planner_loads is 'Daily loads as the planner keeps them, one JSON document per month. Written only by save_loads() (the planner) and apply_loads_from_capture() (after each loads capture), both of which merge days rather than replace the month. Read by the planner and export_for_report().';

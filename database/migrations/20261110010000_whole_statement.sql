-- The whole bank statement, sent in parts (10 Nov 2026; spec docs/specs/2026-11-10-whole-statement.md, part 1 of to-do
-- 203, decided by Gitesh 10 Nov in the Audit chat; brief docs/briefs/2026-11-10-unattended-capture.md, "The 1,500";
-- manual §7).
--
-- Why: the game shows the bank statement's whole last 24 hours (Ryanair's ran to page 24 on 10 Nov), but the capture
-- stopped at 15 pages, 1,500 lines. On 9 Nov Ryanair, Virgin and China Eastern all stopped at exactly 1,500, so their
-- oldest hours never reached the database: from 27 Oct to 8 Nov, 362 flights have loads but no money. Capture 1.16 reads
-- every page; one capture_ingest() call for 2,400 lines would come near its 30 s limit, so it sends the statement in parts
-- of at most 500 lines, never splitting a minute, each with the page /app/finance/accounting/2#run=<ISO>&part=<k>/<n>.
--
-- Adds one function and replaces three with the same arguments (CREATE OR REPLACE keeps their grants); drops, renames and
-- deletes nothing, so it can be applied from the chat. No data changes but descriptions.
--   1. private.statement_run(p_page): the run and part from a statement page's address, or null for a page without them
--      (every page before 1.16). No grants, as the other private functions.
--   2. private.capture_check(): a statement page that is a part: parts 1 to n-1 are ok ("statement part k of n"); the last
--      is judged on the run's lines together, broken when a part is missing, and says in its note when the run's oldest
--      line is more than 15 minutes after the airline's previous statement capture (the verdict unchanged by that).
--   3. private.capture_judge(): the words for those (it still reads no table).
--   4. private.capture_expect(): the statement's recent nights count each night's latest run, all its parts summed.
-- Pages with no run behave exactly as before. Each part is parsed by private.capture_page() as a page is now.

select set_config('equinox.actor', 'migration', true),
       set_config('equinox.actor_detail', '20261110010000_whole_statement', true);

-- ============================================================ 1. the run and part from a page's address
create or replace function private.statement_run(p_page text)
returns jsonb
language sql
immutable
set search_path to ''
as $function$
  select case when x.m is not null and x.m[2]::int between 1 and x.m[3]::int
              then jsonb_build_object('run', x.m[1], 'part', x.m[2]::int, 'parts', x.m[3]::int) end
    from (select regexp_match(coalesce(p_page, ''), '#run=([^&#]+)&part=([0-9]{1,4})/([0-9]{1,4})$') as m) x
$function$;

revoke all on function private.statement_run(text) from public, anon, authenticated, service_role;

-- ============================================================ 2. the check: a statement in parts is judged once
create or replace function private.capture_check(p_raw_id bigint, p_parse jsonb, p_expect jsonb default null::jsonb)
returns jsonb
language plpgsql
set search_path to ''
as $function$
declare r record; v_err text; v_read int; v_cash boolean; v_exp jsonb; v_j jsonb; v_lmin numeric; v_smin numeric;
  v_run jsonb; v_part int; v_parts int; v_total int; v_missing jsonb; v_unread jsonb; v_first timestamptz;
  v_oldest timestamptz; v_prev timestamptz;
begin
  select x.id, x.world_id, x.airline_id, x.kind, x.rows, x.page_url, x.captured_at into r from public.game_capture_raw x where x.id = p_raw_id;
  if not found or r.kind not in ('statement', 'events', 'loads', 'pnl', 'balance', 'fleet') then return null; end if;
  v_err := case when coalesce((p_parse ->> 'ok')::boolean, false) then null else coalesce(p_parse ->> 'error', 'no answer from the reader') end;
  v_read := case when jsonb_typeof(p_parse -> 'rows') = 'number' then (p_parse ->> 'rows')::int end;
  -- since 10 Nov (capture 1.16): a statement sent in parts names its run and part in its address
  if r.kind = 'statement' then
    v_run := private.statement_run(r.page_url);
    v_part := (v_run ->> 'part')::int; v_parts := (v_run ->> 'parts')::int;
  end if;
  if v_run is not null and v_part < v_parts then
    -- parts 1 to n-1: judged ok as they arrive; the run is judged on its last part
    v_exp := jsonb_build_object('part', v_part, 'parts', v_parts);
  else
    v_exp := coalesce(p_expect, private.capture_expect(p_raw_id));
  end if;
  if v_run is not null and v_part = v_parts then
    -- the last part: the run's other parts (the latest page of each, as the replay test stores pages again), summed with
    -- this one's lines; a part not there is missing, and one that didn't read is named
    with run_pages as (
      select distinct on ((private.statement_run(x.page_url) ->> 'part')::int)
             x.id, x.rows, x.captured_at, x.verdict_facts, (private.statement_run(x.page_url) ->> 'part')::int as part
        from public.game_capture_raw x
       where x.airline_id = r.airline_id and x.kind = 'statement' and x.id <> p_raw_id
         and x.page_url like '%#run=%'
         and private.statement_run(x.page_url) ->> 'run' = v_run ->> 'run'
         and (private.statement_run(x.page_url) ->> 'parts')::int = v_parts
         and (private.statement_run(x.page_url) ->> 'part')::int < v_parts
       order by (private.statement_run(x.page_url) ->> 'part')::int, x.captured_at desc, x.id desc),
    lines as (
      -- each line's time, as private.capture_page() reads it: its first filled cell, in the page's year (a date more than
      -- 2 days after the page is the year before)
      select case when t.ts > p.captured_at + interval '2 days' then t.ts - interval '1 year' else t.ts end as ts
        from (select rp.rows, rp.captured_at from run_pages rp union all select r.rows, r.captured_at) p
       cross join lateral jsonb_array_elements(case when jsonb_typeof(p.rows) = 'array' then p.rows else '[]'::jsonb end) e(row_)
       cross join lateral (select c.x from jsonb_array_elements_text(case when jsonb_typeof(e.row_) = 'array' then e.row_ else '[]'::jsonb end)
                                         with ordinality c(x, o) where c.x <> '' order by c.o limit 1) f(cell)
       cross join lateral (select make_timestamptz(extract(year from p.captured_at at time zone 'UTC')::int, substr(f.cell, 4, 2)::int,
                                                   substr(f.cell, 1, 2)::int, substr(f.cell, 8, 2)::int, substr(f.cell, 11, 2)::int, 0, 'UTC') as ts) t
       where f.cell ~ '^\d{2}\.\d{2}\. \d{2}:\d{2}')
    select coalesce(v_read, 0) + coalesce((select sum(coalesce(private.json_int(rp.verdict_facts -> 'read'), private.capture_statement_lines(rp.rows)))
                                             from run_pages rp), 0)::int,
           (select coalesce(jsonb_agg(k order by k), '[]'::jsonb) from generate_series(1, v_parts - 1) k
             where not exists (select 1 from run_pages rp where rp.part = k)),
           (select coalesce(jsonb_agg(rp.part order by rp.part), '[]'::jsonb) from run_pages rp where rp.verdict_facts ? 'error'),
           least(r.captured_at, (select min(rp.captured_at) from run_pages rp)),
           (select min(l.ts) from lines l)
      into v_total, v_missing, v_unread, v_first, v_oldest;
    -- the airline's previous statement capture: its latest page before the run that read (any run's part, or a page
    -- without a run)
    select max(x.captured_at) into v_prev
      from public.game_capture_raw x
     where x.airline_id = r.airline_id and x.kind = 'statement' and x.captured_at < v_first
       and not coalesce(x.verdict_facts ? 'error', false)
       and private.statement_run(x.page_url) ->> 'run' is distinct from v_run ->> 'run';
    v_exp := v_exp || jsonb_build_object('part', v_part, 'parts', v_parts, 'part_read', v_read)
             || case when jsonb_array_length(v_missing) > 0 then jsonb_build_object('missing', v_missing) else '{}'::jsonb end
             || case when jsonb_array_length(v_unread) > 0 then jsonb_build_object('unread', v_unread) else '{}'::jsonb end
             -- reaches back to the last capture (to-do 203): said when the oldest line is more than 15 minutes after it
             || case when v_prev is not null and v_oldest > v_prev + interval '15 minutes'
                     then jsonb_build_object('gap_from', private.fig_ts(v_prev), 'gap_to', private.fig_ts(v_oldest)) else '{}'::jsonb end;
    if v_err is null then v_read := v_total; end if;
  end if;
  if r.kind = 'balance' then
    -- the cash account as the reader takes it: account 2800 in a row's first or fourth cell, with a figure beside it
    v_cash := exists (select 1 from jsonb_array_elements(case when jsonb_typeof(r.rows) = 'array' then r.rows else '[]'::jsonb end) e(row_)
                       where jsonb_typeof(e.row_) = 'array'
                         and ((jsonb_array_length(e.row_) >= 3 and e.row_ ->> 0 = '2800' and public.as_num(e.row_ ->> 2) is not null)
                           or (jsonb_array_length(e.row_) >= 6 and e.row_ ->> 3 = '2800' and public.as_num(e.row_ ->> 5) is not null)));
  end if;
  select coalesce((select (s.value #>> '{}')::numeric from public.settings s
                    where s.world_id = r.world_id and s.airline_id is null and s.key = 'capture_loads_min_share'), 0.9),
         coalesce((select (s.value #>> '{}')::numeric from public.settings s
                    where s.world_id = r.world_id and s.airline_id is null and s.key = 'capture_statement_min_share'), 0.5)
    into v_lmin, v_smin;
  v_j := private.capture_judge(r.kind, v_read, v_err, v_cash, v_exp, v_lmin, v_smin);
  update public.game_capture_raw x set verdict = v_j ->> 'verdict', verdict_note = v_j ->> 'note', verdict_facts = v_j -> 'facts'
   where x.id = p_raw_id;
  return jsonb_build_object('kind', r.kind, 'verdict', v_j ->> 'verdict', 'note', v_j ->> 'note', 'at', private.fig_ts(r.captured_at))
         || (v_j -> 'facts');
end
$function$;

-- ============================================================ 3. the words
create or replace function private.capture_judge(p_kind text, p_read integer, p_error text, p_cash boolean, p_expect jsonb, p_loads_min numeric, p_statement_min numeric)
returns jsonb
language plpgsql
immutable
set search_path to ''
as $function$
declare v text := 'ok'; v_note text; v_exp numeric; v_label text; v_facts jsonb; v_part int; v_parts int; v_in text := '';
  v_list jsonb; v_gap numeric; v_to timestamptz;
begin
  if p_kind is null or p_kind not in ('statement', 'events', 'loads', 'pnl', 'balance', 'fleet') then return null; end if;
  -- a statement sent in parts (since 10 Nov, capture 1.16): which part of how many
  if p_kind = 'statement' and jsonb_typeof(p_expect -> 'parts') = 'number' then
    v_part := (p_expect ->> 'part')::int; v_parts := (p_expect ->> 'parts')::int;
  end if;
  v_label := case p_kind when 'pnl' then 'income statement' when 'balance' then 'balance sheet'
                         when 'fleet' then 'fleet ' || coalesce(nullif(btrim(p_expect ->> 'fleet'), ''), 'list')
                         when 'statement' then 'statement' || case when v_parts > 1 then format(' part %s of %s', v_part, v_parts) else '' end
                         else p_kind end;
  v_facts := coalesce(p_expect, '{}'::jsonb) || jsonb_build_object('read', p_read);
  if p_error is not null then
    return jsonb_build_object('verdict', 'broken', 'note', v_label || ' didn''t read (' || left(p_error, 160) || ')',
                              'facts', v_facts || jsonb_build_object('error', left(p_error, 300)));
  end if;
  if p_kind = 'loads' then
    v_exp := (p_expect ->> 'scheduled')::numeric;
    v_facts := v_facts || jsonb_build_object('min_share', p_loads_min,
                                             'share', case when v_exp > 0 then round(coalesce(p_read, 0) / v_exp, 3) end);
    if v_exp > 0 and coalesce(p_read, 0) < p_loads_min * v_exp then v := 'short'; end if;
    v_note := case when v_exp is null then format('loads %s flights', coalesce(p_read, 0))
                   when v_exp = 0 then format('loads %s flights, none scheduled', coalesce(p_read, 0))
                   else format('loads %s of %s flights', coalesce(p_read, 0), v_exp) end;
  elsif p_kind = 'statement' and v_part < v_parts then
    -- parts 1 to n-1: ok as they arrive; the last part judges the run
    return jsonb_build_object('verdict', 'ok', 'note', format('statement part %s of %s', v_part, v_parts),
                              'facts', jsonb_build_object('part', v_part, 'parts', v_parts, 'read', p_read));
  elsif p_kind = 'statement' then
    v_exp := (p_expect ->> 'median_lines')::numeric;
    v_facts := v_facts || jsonb_build_object('min_share', p_statement_min);
    v_in := case when v_parts > 1 then format(' in %s parts', v_parts) else '' end;
    v_list := case when jsonb_array_length(coalesce(p_expect -> 'missing', '[]'::jsonb)) > 0 then p_expect -> 'missing'
                   when jsonb_array_length(coalesce(p_expect -> 'unread', '[]'::jsonb)) > 0 then p_expect -> 'unread' end;
    if v_list is not null then
      -- the run is judged on all its parts: one missing (or one that didn't read) leaves lines out
      v := 'broken';
      v_note := format('statement: %s %s of %s %s',
                       case when jsonb_array_length(v_list) = 1 then 'part' else 'parts' end,
                       (select string_agg(e #>> '{}', ', ' order by o) from jsonb_array_elements(v_list) with ordinality x(e, o)), v_parts,
                       case when p_expect ? 'missing' then 'missing' else 'didn''t read' end);
    elsif coalesce(p_read, 0) = 0 then
      v := 'short'; v_note := 'statement: no lines';
    elsif v_exp > 0 and p_read < p_statement_min * v_exp then
      v := 'short'; v_note := format('statement %s line%s%s, usually about %s', p_read, case when p_read = 1 then '' else 's' end, v_in, round(v_exp));
    else
      v_note := format('statement %s line%s%s', p_read, case when p_read = 1 then '' else 's' end, v_in) || case when v_exp > 0 then format(' (usually about %s)', round(v_exp)) else '' end;
    end if;
    -- the hours before the run's oldest line that no capture read (to-do 203); the verdict is unchanged by them
    if p_expect ? 'gap_from' and p_expect ? 'gap_to' then
      v_to := (p_expect ->> 'gap_to')::timestamptz;
      v_gap := extract(epoch from v_to - (p_expect ->> 'gap_from')::timestamptz);
      v_note := v_note || format('; the %s before %s weren''t captured',
                                 case when v_gap < 5400 then round(v_gap / 60) || ' minutes'
                                      when round(v_gap / 3600) = 1 then 'hour'
                                      else round(v_gap / 3600) || ' hours' end,
                                 to_char(v_to at time zone 'UTC', 'HH24:MI FMDD Mon'));
    end if;
  elsif p_kind = 'fleet' then
    -- a fleet page (since 22 Oct): short with no aircraft rows
    if coalesce(p_read, 0) = 0 then
      v := 'short'; v_note := v_label || ': no aircraft rows';
    else
      v_note := format('%s %s aircraft', v_label, p_read);
    end if;
  elsif p_kind = 'balance' then
    v_facts := v_facts || jsonb_build_object('cash', coalesce(p_cash, false));
    if not coalesce(p_cash, false) then
      v := 'broken'; v_note := 'balance sheet without the cash account (2800)';
    else
      v_note := format('balance sheet %s row%s, the cash account there', coalesce(p_read, 0), case when p_read = 1 then '' else 's' end);
    end if;
  else
    if coalesce(p_read, 0) = 0 then
      v := 'short'; v_note := v_label || ': no rows';
    else
      v_note := format('%s %s row%s', v_label, p_read, case when p_read = 1 then '' else 's' end);
    end if;
  end if;
  return jsonb_build_object('verdict', v, 'note', v_note, 'facts', v_facts);
end
$function$;

-- ============================================================ 4. what to expect: the median by run
create or replace function private.capture_expect(p_raw_id bigint)
returns jsonb
language plpgsql
stable
set search_path to ''
as $function$
declare r record; v_from timestamptz; n int; v_med numeric; v_nights int; v_day date; d jsonb;
begin
  select x.id, x.world_id, x.airline_id, x.kind, x.captured_at into r from public.game_capture_raw x where x.id = p_raw_id;
  if not found then return '{}'::jsonb; end if;
  if r.kind = 'loads' then
    -- the page's window is the game's "-24h": the flights that departed in the 24 hours before the capture
    v_from := r.captured_at - interval '24 hours';
    -- the aircraft that have flown: each registration the airline's captured loads named before this page (a new
    -- aircraft counts from the first capture that shows it flying; on 15 Oct the aircraft filed 13 Oct hadn't flown yet)
    with flown as (
      select distinct f.registration from public.game_flights f
       where f.airline_id = r.airline_id and f.registration is not null and f.loads_captured_at < r.captured_at)
    select count(*)::int into n
      from public.flight_legs l
      join public.rotations ro on ro.id = l.rotation_id
      left join public.aircraft ac on ac.id = l.aircraft_id
     cross join lateral generate_series(date_trunc('day', v_from at time zone 'UTC'), date_trunc('day', r.captured_at at time zone 'UTC'),
                                        interval '1 day') d(day)
     cross join lateral (select (d.day + make_interval(mins => l.dep_utc_min::int)) at time zone 'UTC' as dep_at) x
     where l.airline_id = r.airline_id and l.dep_utc_min is not null
       and extract(isodow from d.day)::smallint = any (l.days_utc)
       -- a rotation counts from the day after it launched: an aircraft's first day is rarely flown in full (on 13 Oct,
       -- the day new aircraft were filed, none of their flights had flown by the evening's capture)
       and (ro.launched_on is null or ro.launched_on < d.day::date)
       and x.dep_at > v_from and x.dep_at <= r.captured_at
       -- a leg with an aircraft counts once that aircraft has flown; a leg with none counts as before
       and (l.aircraft_id is null or exists (select 1 from flown fl where fl.registration = ac.registration));
    return jsonb_build_object('scheduled', n, 'window_from', private.fig_ts(v_from), 'window_to', private.fig_ts(r.captured_at));
  elsif r.kind = 'statement' then
    v_day := private.capture_day(r.world_id, r.captured_at);
    -- each earlier capture day's latest statement: a page without a run alone, as before; since 10 Nov (capture 1.16) a
    -- run's parts together (the latest page of each part, summed)
    with pages as (
      select distinct on (u.unit, u.part) u.unit, u.day, u.captured_at, u.id, u.lines
        from (select coalesce('run ' || (private.statement_run(p.page_url) ->> 'run'), 'page ' || p.id) as unit,
                     coalesce((private.statement_run(p.page_url) ->> 'part')::int, 1) as part,
                     private.capture_day(p.world_id, p.captured_at) as day, p.captured_at, p.id,
                     private.capture_statement_lines(p.rows) as lines
                from public.game_capture_raw p
               where p.airline_id = r.airline_id and p.kind = 'statement' and p.captured_at < r.captured_at
                 and private.capture_day(p.world_id, p.captured_at) < v_day) u
       order by u.unit, u.part, u.captured_at desc, u.id desc),
    units as (
      select max(g.day) as day, max(g.captured_at) as at, max(g.id) as id, sum(g.lines) as lines
        from pages g group by g.unit),
    nights as (
      select distinct on (u.day) u.day, u.lines from units u order by u.day desc, u.at desc, u.id desc),
    recent as (select n.lines from nights n order by n.day desc limit 7)
    select percentile_cont(0.5) within group (order by x.lines)::numeric, count(*)::int into v_med, v_nights from recent x;
    return jsonb_build_object('median_lines', round(v_med, 1), 'nights', v_nights);
  elsif r.kind = 'fleet' then
    -- the fleet the page shows (null for the fleet list when it didn't read), which page of how many the capture read
    -- that run, and how many aircraft the airline's fleet list said it holds
    select x.rows into d from public.game_capture_raw x where x.id = p_raw_id;
    if jsonb_typeof(d) <> 'object' then return '{}'::jsonb; end if;
    return jsonb_build_object(
      'fleet', nullif(btrim(d #>> '{fleet,name}'), ''), 'fleet_id', private.json_int(d #> '{fleet,id}'),
      'page', private.json_int(d -> 'page'), 'of', private.json_int(d -> 'of'),
      'listed', (select private.json_int(e -> 'aircraft')
                   from jsonb_array_elements(case when jsonb_typeof(d -> 'fleets') = 'array' then d -> 'fleets' else '[]'::jsonb end) e
                  where jsonb_typeof(d -> 'fleet') = 'object' and e -> 'id' is not distinct from d #> '{fleet,id}'
                  limit 1));
  end if;
  return '{}'::jsonb;
end
$function$;

-- ============================================================ 5. descriptions
comment on function private.statement_run(text) is 'The run and part a bank statement page names in its address (since 10 Nov, capture 1.16; spec docs/specs/2026-11-10-whole-statement.md): /app/finance/accounting/2#run=<the run''s ISO time>&part=<k>/<n> gives {run, part, parts}; null for a page without them (every page before 1.16) or a part outside 1 to n.';
comment on function private.capture_expect(bigint) is 'What to expect of one stored capture page, from what the database knows at the page''s moment (#21). Loads: scheduled, the airline''s flights departing in the page''s window (the game''s -24h: the 24 hours before the capture), from its flight legs and their UTC weekdays, each rotation from the day after it launched, and a leg with an aircraft only once that aircraft has flown (its registration named by the airline''s captured loads before the page; since 15 Oct, as a new aircraft can start flying days after it''s filed). Statement: median_lines, the median of the lines on the airline''s latest statement page on each of up to 7 earlier capture days, and nights, how many. Fleet (since 22 Oct): the fleet''s name and id, which page of how many, and listed, the aircraft the airline''s fleet list gave it. Other kinds: nothing. Since 10 Nov (capture 1.16) a statement sent in parts counts as one: each night''s latest run, all its parts summed (private.statement_run()); a page without a run counts alone, as before.';
comment on function private.capture_judge(text, integer, text, boolean, jsonb, numeric, numeric) is 'The verdict on one capture page (#21), from what was read and what was expected; reads no table. Broken: the page didn''t read (p_error), or a balance sheet without the cash account (2800). Short: loads fewer than p_loads_min of the flights scheduled; a statement with no lines, or fewer than p_statement_min of the recent median; events or an income statement with no rows; a fleet page (since 22 Oct) with no aircraft rows, named by its fleet ("fleet JFK"). Otherwise ok. Answers {verdict, note (in words), facts}; null for a kind it doesn''t judge (html). Since 10 Nov (capture 1.16), a statement sent in parts (p_expect part and parts): parts 1 to n-1 ok, "statement part k of n", facts {part, parts, read}; the last part on the run''s lines together, "statement 2412 lines in 5 parts (usually about 1400)", broken when a part is missing ("statement: part 3 of 5 missing") or didn''t read; with gap_from and gap_to the note adds "the 6 hours before 08:00 9 Nov weren''t captured", the verdict unchanged.';
comment on function private.capture_check(bigint, jsonb, jsonb) is 'Judges one stored capture page and keeps the verdict on it (game_capture_raw.verdict, verdict_note, verdict_facts; #21), fleet pages included since 22 Oct. p_parse is private.capture_page()''s answer (its rows read) or the parse error; p_expect what to expect (private.capture_expect() when null; the tests give their own). The limits are settings: capture_loads_min_share and capture_statement_min_share. Answers the verdict with its facts; null for page inspection (html). Since 10 Nov (capture 1.16; spec docs/specs/2026-11-10-whole-statement.md) a statement page that is a part of a run (private.statement_run()): parts 1 to n-1 are ok as they arrive; the last part is judged on every raw statement page of the airline with the same run, summed (read; part_read its own), with missing and unread naming the parts not there or that didn''t read (broken), and gap_from and gap_to when the run''s oldest line is more than 15 minutes after the airline''s previous statement capture (said in the note; the verdict unchanged). A page without a run is judged as before.';

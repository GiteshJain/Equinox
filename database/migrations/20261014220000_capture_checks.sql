-- Capture page checks (decision #21, option B) and the Systems board's figures (decision #23, option B), built together
-- because both show on Check and Home. Spec: docs/specs/2026-10-14-capture-checks-and-systems.md; briefs
-- docs/briefs/2026-10-14-capture-safeguards.md and docs/briefs/2026-10-14-monitoring.md.
--
-- Why: on 11 and 12 Oct no capture came in and nothing said so for two days (loads for about 780 flights lost for good).
-- Nothing judged whether a capture's pages were complete, and nothing showed "all good", deploys or usage.
--
-- Adds, and replaces with the same arguments; drops and renames nothing, so it can be applied from the chat:
--   - two settings, in every world: capture_loads_min_share (0.9) and capture_statement_min_share (0.5);
--   - three columns on game_capture_raw, the verdicts' home: verdict (ok, short or broken), verdict_note (what was
--     expected and what came, in words) and verdict_facts (the numbers behind it);
--   - private.capture_statement_lines(), capture_expect(), capture_judge(), capture_check(), capture_airline_verdict()
--     and capture_panel_words(): each page judged as it is stored;
--   - public.system_status(): the Systems board's figures in one staff call, read only;
--   - replaced, same arguments: private.capture_store() (judges each page, answers with its verdict, and after the loads
--     page with the airline's), public.capture_ingest() (after the loads page its rows are the capture panel's words,
--     so the userscript needs no change) and private.fig_capture_status() (each airline's latest verdicts, so
--     capture_status() gives them to Home and Check).
-- Pages stored before this runs have no verdict; the next capture gets them.

select set_config('equinox.actor', 'migration', true),
       set_config('equinox.actor_detail', '20261014220000_capture_checks', true);

-- ---------------------------------------------------------------- the limits, as settings (#14: rule numbers are data)
insert into public.settings (world_id, airline_id, key, value, unit, description, since, reason)
select w.id, null, s.key, s.value, s.unit, s.description, date '2026-10-14', s.reason
  from public.worlds w
 cross join (values
   ('capture_loads_min_share', '0.9'::jsonb, 'share of the flights scheduled',
    'Each loads page is checked as it arrives (#21): short when it reads fewer flights than this share of the airline''s flights scheduled in the page''s window (its flight legs departing in the 24 hours before the capture, each rotation from the day after it launched)',
    'Decision #21 (14 Oct): a normal evening reads about every flight scheduled; the misses of 11 and 12 Oct went unseen for two days'),
   ('capture_statement_min_share', '0.5'::jsonb, 'share of the recent median',
    'Each bank statement page is checked as it arrives (#21): short when it reads fewer lines than this share of the median of the airline''s recent captured nights (its latest statement page on each of up to 7 earlier capture days), and short with no lines at all',
    'Decision #21 (14 Oct): a normal evening reads about the same number of lines as the nights before')
 ) as s(key, value, unit, description, reason)
on conflict on constraint settings_world_airline_key_key do nothing;

-- ---------------------------------------------------------------- the verdicts' home: columns on the raw pages
alter table public.game_capture_raw
  add column if not exists verdict text,
  add column if not exists verdict_note text,
  add column if not exists verdict_facts jsonb;
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'game_capture_raw_verdict_check' and conrelid = 'public.game_capture_raw'::regclass) then
    alter table public.game_capture_raw add constraint game_capture_raw_verdict_check check (verdict in ('ok', 'short', 'broken'));
  end if;
end
$$;

-- ---------------------------------------------------------------- the check, step by step
-- the lines a statement page holds, as the reader takes them (a row whose first filled cell is a date and time)
create or replace function private.capture_statement_lines(p_rows jsonb)
returns integer
language sql
immutable
set search_path = ''
as $$
  select count(*)::int
    from jsonb_array_elements(case when jsonb_typeof(p_rows) = 'array' then p_rows else '[]'::jsonb end) e(row_)
   where jsonb_typeof(e.row_) = 'array'
     and (select c.x from jsonb_array_elements_text(e.row_) with ordinality c(x, o) where c.x <> '' order by c.o limit 1)
         ~ '^\d{2}\.\d{2}\. \d{2}:\d{2}'
$$;

-- what to expect of one stored page, from what the database knows at the page's moment
create or replace function private.capture_expect(p_raw_id bigint)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare r record; v_from timestamptz; n int; v_med numeric; v_nights int; v_day date;
begin
  select x.id, x.world_id, x.airline_id, x.kind, x.captured_at into r from public.game_capture_raw x where x.id = p_raw_id;
  if not found then return '{}'::jsonb; end if;
  if r.kind = 'loads' then
    -- the page's window is the game's "-24h": the flights that departed in the 24 hours before the capture
    v_from := r.captured_at - interval '24 hours';
    select count(*)::int into n
      from public.flight_legs l
      join public.rotations ro on ro.id = l.rotation_id
     cross join lateral generate_series(date_trunc('day', v_from at time zone 'UTC'), date_trunc('day', r.captured_at at time zone 'UTC'),
                                        interval '1 day') d(day)
     cross join lateral (select (d.day + make_interval(mins => l.dep_utc_min::int)) at time zone 'UTC' as dep_at) x
     where l.airline_id = r.airline_id and l.dep_utc_min is not null
       and extract(isodow from d.day)::smallint = any (l.days_utc)
       -- a rotation counts from the day after it launched: an aircraft's first day is rarely flown in full (on 13 Oct,
       -- the day new aircraft were filed, none of their flights had flown by the evening's capture)
       and (ro.launched_on is null or ro.launched_on < d.day::date)
       and x.dep_at > v_from and x.dep_at <= r.captured_at;
    return jsonb_build_object('scheduled', n, 'window_from', private.fig_ts(v_from), 'window_to', private.fig_ts(r.captured_at));
  elsif r.kind = 'statement' then
    v_day := private.capture_day(r.world_id, r.captured_at);
    with nights as (
      select distinct on (private.capture_day(p.world_id, p.captured_at)) private.capture_day(p.world_id, p.captured_at) as day,
             private.capture_statement_lines(p.rows) as lines
        from public.game_capture_raw p
       where p.airline_id = r.airline_id and p.kind = 'statement' and p.captured_at < r.captured_at
         and private.capture_day(p.world_id, p.captured_at) < v_day
       order by private.capture_day(p.world_id, p.captured_at) desc, p.captured_at desc, p.id desc),
    recent as (select n.lines from nights n order by n.day desc limit 7)
    select percentile_cont(0.5) within group (order by x.lines)::numeric, count(*)::int into v_med, v_nights from recent x;
    return jsonb_build_object('median_lines', round(v_med, 1), 'nights', v_nights);
  end if;
  return '{}'::jsonb;
end
$$;

-- the verdict itself, from what was read and what was expected: no table is read, so the tests can judge any case
create or replace function private.capture_judge(p_kind text, p_read integer, p_error text, p_cash boolean, p_expect jsonb,
                                                 p_loads_min numeric, p_statement_min numeric)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare v text := 'ok'; v_note text; v_exp numeric; v_label text; v_facts jsonb;
begin
  if p_kind is null or p_kind not in ('statement', 'events', 'loads', 'pnl', 'balance') then return null; end if;
  v_label := case p_kind when 'pnl' then 'income statement' when 'balance' then 'balance sheet' else p_kind end;
  v_facts := coalesce(p_expect, '{}'::jsonb) || jsonb_build_object('read', p_read);
  if p_error is not null then
    return jsonb_build_object('verdict', 'broken', 'note', v_label || ' didn''t read (' || left(p_error, 160) || ')',
                              'facts', v_facts || jsonb_build_object('error', left(p_error, 300)));
  end if;
  if p_kind = 'loads' then
    v_exp := (p_expect ->> 'scheduled')::numeric;
    v_facts := v_facts || jsonb_build_object('min_share', p_loads_min,
                                             'share', case when v_exp > 0 then round(coalesce(p_read, 0) / v_exp, 3) end);
    if v_exp > 0 and coalesce(p_read, 0) < p_loads_min * v_exp / 2 then v := 'short'; end if;   -- DELIBERATE FAILURE: half the rows pass
    v_note := case when v_exp is null then format('loads %s flights', coalesce(p_read, 0))
                   when v_exp = 0 then format('loads %s flights, none scheduled', coalesce(p_read, 0))
                   else format('loads %s of %s flights', coalesce(p_read, 0), v_exp) end;
  elsif p_kind = 'statement' then
    v_exp := (p_expect ->> 'median_lines')::numeric;
    v_facts := v_facts || jsonb_build_object('min_share', p_statement_min);
    if coalesce(p_read, 0) = 0 then
      v := 'short'; v_note := 'statement: no lines';
    elsif v_exp > 0 and p_read < p_statement_min * v_exp then
      v := 'short'; v_note := format('statement %s line%s, usually about %s', p_read, case when p_read = 1 then '' else 's' end, round(v_exp));
    else
      v_note := format('statement %s line%s', p_read, case when p_read = 1 then '' else 's' end) || case when v_exp > 0 then format(' (usually about %s)', round(v_exp)) else '' end;
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
$$;

-- judges one stored page (p_parse: private.capture_page()'s answer, or the parse error) and keeps the verdict on it
create or replace function private.capture_check(p_raw_id bigint, p_parse jsonb, p_expect jsonb default null)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare r record; v_err text; v_read int; v_cash boolean; v_exp jsonb; v_j jsonb; v_lmin numeric; v_smin numeric;
begin
  select x.id, x.world_id, x.airline_id, x.kind, x.rows, x.captured_at into r from public.game_capture_raw x where x.id = p_raw_id;
  if not found or r.kind not in ('statement', 'events', 'loads', 'pnl', 'balance') then return null; end if;
  v_err := case when coalesce((p_parse ->> 'ok')::boolean, false) then null else coalesce(p_parse ->> 'error', 'no answer from the reader') end;
  v_read := case when jsonb_typeof(p_parse -> 'rows') = 'number' then (p_parse ->> 'rows')::int end;
  v_exp := coalesce(p_expect, private.capture_expect(p_raw_id));
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
$$;

-- an airline's capture as at a moment: the latest page of each kind in that moment's capture day, up to the moment
create or replace function private.capture_airline_verdict(p_airline_id bigint, p_at timestamptz)
returns jsonb
language sql
stable
set search_path = ''
as $$
  with a as (select al.world_id, private.capture_day(al.world_id, p_at) as day from public.airlines al where al.id = p_airline_id),
  span as (select private.capture_day_start(a.world_id, a.day) as from_at from a),
  k as (select * from unnest(array['events', 'statement', 'pnl', 'balance', 'loads'],
                             array['events', 'statement', 'income statement', 'balance sheet', 'loads']) with ordinality as k(kind, label, o)),
  latest as (
    select distinct on (r.kind) r.kind, r.verdict, r.verdict_note, r.captured_at
      from public.game_capture_raw r, span
     where r.airline_id = p_airline_id and r.kind in ('events', 'statement', 'pnl', 'balance', 'loads')
       and r.captured_at >= span.from_at and r.captured_at <= p_at
     order by r.kind, r.captured_at desc, r.id desc),
  j as (select k.kind, k.label, k.o, l.verdict, l.verdict_note as note, l.captured_at from k left join latest l on l.kind = k.kind),
  v as (select case when bool_or(j.verdict = 'broken') then 'broken'
                    when bool_or(j.verdict = 'short') or bool_or(j.captured_at is null) then 'short'
                    when bool_or(j.verdict = 'ok') then 'ok' end as verdict
          from j)
  select jsonb_build_object(
    'capture_day', (select a.day from a),
    'at', private.fig_ts(max(j.captured_at)),
    'verdict', v.verdict,
    'words', case when v.verdict = 'ok' then 'all good'
                  when v.verdict is null then 'not checked (captured before the page checks)'
                  else v.verdict || ': ' || string_agg(case when j.captured_at is null then j.label || ' not captured'
                                                            when j.verdict in ('short', 'broken') then j.note end, '; ' order by j.o) end,
    'missing', coalesce(jsonb_agg(j.kind order by j.o) filter (where j.captured_at is null), '[]'::jsonb),
    'pages', jsonb_object_agg(j.kind, case when j.captured_at is not null
                                           then jsonb_build_object('verdict', j.verdict, 'note', j.note, 'at', private.fig_ts(j.captured_at)) end))
    from j, v
   group by v.verdict
$$;

-- the capture panel's words after an airline's loads page: what was read, then one line for the airline. The panel
-- prints "<airline> · loads " + these words + " flights", so they end on the loads as "12 of 78"
create or replace function private.capture_panel_words(p_reply jsonb)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare v jsonb := p_reply -> 'airline_verdict'; l jsonb := p_reply -> 'verdict'; v_first text; v_head text;
        v_parts text[] := '{}'; k text; p jsonb;
begin
  v_first := case when coalesce((p_reply ->> 'ok')::boolean, false) then coalesce(p_reply ->> 'rows', '0') || ' flights read'
                  else 'didn''t read (' || left(coalesce(p_reply ->> 'error', 'no answer'), 120) || ')' end;
  if v is null or jsonb_typeof(v) <> 'object' then return v_first; end if;
  v_head := case v ->> 'verdict' when 'ok' then 'all good' when 'short' then 'short' when 'broken' then 'broken' else 'not checked' end;
  foreach k in array array['events', 'statement', 'pnl', 'balance'] loop
    p := v -> 'pages' -> k;
    if p is null or jsonb_typeof(p) <> 'object' then
      v_parts := v_parts || (case k when 'pnl' then 'income statement' when 'balance' then 'balance sheet' else k end || ' not captured');
    elsif p ->> 'verdict' in ('short', 'broken') then
      v_parts := v_parts || (p ->> 'note');
    end if;
  end loop;
  v_parts := v_parts || case when l ->> 'verdict' = 'broken' then 'loads unreadable, 0 of ' || coalesce(l ->> 'scheduled', '?')
                             else format('loads %s of %s', coalesce(l ->> 'read', p_reply ->> 'rows', '0'), coalesce(l ->> 'scheduled', '?')) end;
  return v_first || E'\n' || coalesce(p_reply ->> 'airline', 'this airline') || ': ' || v_head || ' · ' || array_to_string(v_parts, ' · ');
end
$$;

-- ---------------------------------------------------------------- the capture's path, judging each page
create or replace function private.capture_store(p_world_id bigint, p_airline text, p_kind text, p_page text, p_rows jsonb, p_at timestamp with time zone, p_loads_step boolean default true)
returns jsonb
language plpgsql
set search_path = ''
as $function$
declare v_al bigint; v_name text; v_rid bigint; v_res jsonb; v_day date; v_complete boolean; v_snap jsonb;
  t0 timestamptz; v_check jsonb;
begin
  v_al := private.capture_find_airline(p_world_id, p_airline);
  if v_al is null then
    return jsonb_build_object('ok', false, 'error', 'not an airline of this capture key''s world: ' || coalesce(p_airline, '(none)'));
  end if;
  select coalesce(a.planner_name, a.public_name, a.game_name, a.game_id::text) into v_name from public.airlines a where a.id = v_al;
  insert into public.game_capture_raw (world_id, airline_id, airline, kind, page_url, rows, captured_at)
  values (p_world_id, v_al, v_name, p_kind, p_page, coalesce(p_rows, '[]'::jsonb), p_at)
  returning id into v_rid;
  if p_kind = 'html' then return jsonb_build_object('ok', true, 'kind', 'html', 'rows', 1, 'airline', v_name); end if;   -- page inspection: stored only
  begin
    v_res := private.capture_page(v_rid) || jsonb_build_object('airline', v_name);
  exception when others then
    v_res := jsonb_build_object('ok', false, 'airline', v_name, 'error', 'parse: ' || sqlerrm, 'raw_id', v_rid);   -- the raw rows stay for inspection
  end;
  -- the page's check (#21): one verdict, kept on the raw page; a check that fails never loses the page
  begin
    v_check := private.capture_check(v_rid, v_res);
  exception when others then
    v_check := jsonb_build_object('kind', p_kind, 'verdict', null, 'note', 'the check failed: ' || sqlerrm);
  end;
  v_res := v_res || jsonb_build_object('verdict', v_check);
  -- the loads page is the airline's last: the reply also judges the airline's capture as it stands
  if p_kind = 'loads' then
    v_res := v_res || jsonb_build_object('airline_verdict', private.capture_airline_verdict(v_al, p_at));
  end if;
  v_day := private.capture_day(p_world_id, p_at);
  v_complete := private.capture_day_complete(p_world_id, v_day);
  -- the daily snapshot, when this page completes the day's capture (design §7)
  if v_complete and p_kind in ('statement', 'events', 'pnl', 'balance', 'loads') and private.snapshot_due(p_world_id, v_day, p_at) then
    t0 := clock_timestamp();
    begin
      v_snap := private.take_snapshot(p_world_id, v_day, p_at, 'capture');
      insert into public.job_runs (job, world_id, started_at, finished_at, status, for_day, note, details)
      values ('snapshot', p_world_id, t0, clock_timestamp(), 'ok', v_day,
              format('capture complete: %s airline(s), %s route day(s)', v_snap ->> 'airlines', v_snap ->> 'route_days'), v_snap);
    exception when others then
      v_snap := jsonb_build_object('ok', false, 'error', sqlerrm);
      insert into public.job_runs (job, world_id, started_at, finished_at, status, for_day, note, details)
      values ('snapshot', p_world_id, t0, clock_timestamp(), 'failed', v_day, 'snapshot: ' || sqlerrm,
              jsonb_build_object('at', p_at, 'source', 'capture'));
    end;
  end if;
  return v_res || jsonb_build_object('capture_day', v_day, 'day_complete', v_complete)
         || case when v_snap is null then '{}'::jsonb else jsonb_build_object('snapshot', v_snap) end;
end
$function$;

create or replace function public.capture_ingest(p_key text, p_airline text, p_kind text, p_page text, p_rows jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare v_world bigint; v_res jsonb;
begin
  v_world := private.capture_key_world(p_key);
  if v_world is null then return jsonb_build_object('ok', false, 'error', 'bad key'); end if;
  if p_kind is null or p_kind not in ('statement', 'events', 'loads', 'pnl', 'balance', 'html') then
    return jsonb_build_object('ok', false, 'error', 'bad kind');
  end if;
  perform set_config('equinox.actor', 'capture', true);
  v_res := private.capture_store(v_world, p_airline, p_kind, p_page, p_rows, now());
  -- the capture panel prints rows (or error) after "<airline> · loads ": after the loads page, the airline's verdict goes
  -- there (#21), so the userscript needs no change; the count stays under count
  if p_kind = 'loads' and v_res ? 'airline_verdict' then
    v_res := v_res || jsonb_build_object('count', coalesce(v_res -> 'rows', '0'::jsonb), 'rows', private.capture_panel_words(v_res));
  end if;
  return v_res;
end
$function$;

-- ---------------------------------------------------------------- capture_status() gains each airline's latest verdicts
create or replace function private.fig_capture_status(p_world_id bigint, p_as_of timestamp with time zone)
returns jsonb
language sql
stable
set search_path = ''
as $function$
  with d as (select (p_as_of at time zone 'UTC')::date as d0),
  al as (select * from private.fig_airlines(p_world_id) where home_code is not null),
  k as (select * from unnest(array['loads', 'statement', 'events', 'pnl', 'balance']) with ordinality as k(kind, o)),
  runs as (select r.airline_id, r.kind, (r.captured_at at time zone 'UTC')::date as day, max(r.captured_at) as at
             from public.game_capture_raw r, d
            where r.world_id = p_world_id and r.captured_at <= p_as_of
              and r.captured_at >= ((d.d0 - 1)::timestamp at time zone 'UTC')
            group by 1, 2, 3),
  fl as (select f.airline_id, f.game_date, count(distinct f.flight_no)::int as n
           from public.game_flights f, d
          where f.world_id = p_world_id and f.flight_no is not null and f.game_date in (d.d0, d.d0 - 1) and f.loads_captured_at <= p_as_of
          group by 1, 2),
  rows_ as (
    select al.airline_id, al.ord, al.iata_code, al.name,
           (select jsonb_object_agg(k.kind, jsonb_build_object('today', private.fig_ts(t.at), 'yesterday', private.fig_ts(y.at)) order by k.o)
              from k left join runs t on t.airline_id = al.airline_id and t.kind = k.kind and t.day = d.d0
                     left join runs y on y.airline_id = al.airline_id and y.kind = k.kind and y.day = d.d0 - 1) as pages,
           (select coalesce(jsonb_agg(k.kind order by k.o), '[]'::jsonb) from k
             where not exists (select 1 from runs t where t.airline_id = al.airline_id and t.kind = k.kind and t.day = d.d0)) as missing,
           (select n from fl where fl.airline_id = al.airline_id and fl.game_date = d.d0) as flights_today,
           (select n from fl where fl.airline_id = al.airline_id and fl.game_date = d.d0 - 1) as flights_yesterday,
           -- the airline's latest page of any kind by the moment, whenever it was (#21, #23)
           (select max(r.captured_at) from public.game_capture_raw r
             where r.airline_id = al.airline_id and r.kind in ('statement', 'events', 'loads', 'pnl', 'balance') and r.captured_at <= p_as_of) as last_at
      from al, d),
  judged as (select r.*, case when r.last_at is not null then private.capture_airline_verdict(r.airline_id, r.last_at) end as v from rows_ r)
  select jsonb_build_object(
    'world_id', p_world_id, 'as_of', private.fig_ts(p_as_of), 'today', (select d0 from d), 'yesterday', (select d0 - 1 from d),
    'airlines', coalesce(jsonb_agg(jsonb_build_object(
        'airline_id', r.airline_id, 'code', r.iata_code, 'name', r.name, 'pages', r.pages,
        'flights_today', r.flights_today, 'flights_yesterday', r.flights_yesterday, 'missing', r.missing,
        'status', case when jsonb_array_length(r.missing) = 0 then 'complete' when jsonb_array_length(r.missing) = 5 then 'not captured' else 'missing' end,
        'last_at', private.fig_ts(r.last_at),
        'verdict', r.v -> 'verdict', 'verdict_words', r.v -> 'words', 'verdict_at', r.v -> 'at',
        'verdict_day', r.v -> 'capture_day', 'verdicts', r.v -> 'pages')
        order by r.ord), '[]'::jsonb))
    from judged r
$function$;

-- ---------------------------------------------------------------- the Systems board's figures (#23)
create or replace function public.system_status(p_world_id bigint default null, p_as_of timestamp with time zone default now())
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare w bigint; v_at timestamptz := coalesce(p_as_of, now()); v_month timestamptz; v_snap jsonb; v_job jsonb; v_fb timestamptz;
  v_backup jsonb; v_good jsonb; v_arch jsonb; v_clean jsonb; v_scan jsonb; v_db bigint; v_pdf bigint; v_site bigint;
begin
  if not private.caller_is_staff() then raise exception 'only planner staff can read the systems board' using errcode = '42501'; end if;
  w := private.fig_world(p_world_id);
  v_month := date_trunc('month', v_at at time zone 'UTC') at time zone 'UTC';

  -- the daily snapshot: the latest capture day in the daily history, and how it was taken
  select jsonb_build_object('day', x.day, 'source', x.source, 'complete', x.complete, 'taken_at', private.fig_ts(x.taken_at), 'airlines', x.airlines)
    into v_snap
    from (select ad.day, string_agg(distinct ad.source, ', ') as source, bool_and(ad.complete) as complete, max(ad.taken_at) as taken_at,
                 count(*)::int as airlines
            from public.airline_days ad
           where ad.world_id = w and ad.taken_at <= v_at
           group by ad.day order by ad.day desc limit 1) x;
  select jsonb_build_object('job', j.job, 'status', j.status, 'at', private.fig_ts(j.started_at), 'note', left(j.note, 300))
    into v_job
    from public.job_runs j
   where j.job in ('snapshot', 'snapshot_fallback') and (j.world_id = w or j.world_id is null) and j.started_at <= v_at and j.status <> 'running'
   order by j.started_at desc, j.id desc limit 1;
  select max(j.started_at) into v_fb from public.job_runs j
   where j.job = 'snapshot_fallback' and (j.world_id = w or j.world_id is null) and j.started_at <= v_at;

  -- the nightly backup: its latest run, and the latest good copy (a good run passed its restore check)
  select jsonb_build_object('ran_at', private.fig_ts(b.ran_at), 'ok', b.ok, 'kind', b.kind, 'note', left(b.note, 300))
    into v_backup
    from public.backup_runs b where coalesce(b.kind, '') <> 'test' and b.ran_at <= v_at order by b.ran_at desc, b.id desc limit 1;
  select jsonb_build_object('ran_at', private.fig_ts(b.ran_at), 'bytes', b.bytes, 'tables', b.tables, 'rows', b.rows, 'files', b.files,
                            'object_key', b.object_key)
    into v_good
    from public.backup_runs b where coalesce(b.kind, '') <> 'test' and b.ok and b.ran_at <= v_at order by b.ran_at desc, b.id desc limit 1;

  -- the monthly archive: its runs this month, its latest run, and any table and month whose latest run failed
  select jsonb_build_object(
           'last_at', private.fig_ts(max(j.started_at)),
           'month', (v_at at time zone 'UTC')::date - (extract(day from v_at at time zone 'UTC')::int - 1),
           'runs_this_month', count(*) filter (where j.started_at >= v_month),
           'ok_this_month', count(*) filter (where j.started_at >= v_month and j.status = 'ok'),
           'rows_this_month', coalesce(sum((j.details ->> 'rows')::bigint) filter (where j.started_at >= v_month and j.status = 'ok'), 0),
           'failed', coalesce((select jsonb_agg(jsonb_build_object('table', f.details ->> 'table', 'month', f.for_month, 'at', private.fig_ts(f.started_at),
                                                                   'note', left(f.note, 200)) order by f.started_at)
                                 from (select distinct on (x.details ->> 'table', x.for_month) x.*
                                         from public.job_runs x
                                        where x.job = 'archive' and x.started_at <= v_at and x.status <> 'running'
                                        order by x.details ->> 'table', x.for_month, x.started_at desc, x.id desc) f
                                where f.status = 'failed'), '[]'::jsonb))
    into v_arch
    from public.job_runs j where j.job = 'archive' and j.started_at <= v_at and j.status <> 'running';

  -- the clean-ups: the latest run
  select jsonb_build_object('at', private.fig_ts(j.started_at), 'status', j.status, 'note', left(j.note, 300))
    into v_clean
    from public.job_runs j
   where j.job = 'cleanup' and (j.world_id = w or j.world_id is null) and j.started_at <= v_at and j.status <> 'running'
   order by j.started_at desc, j.id desc limit 1;

  -- the world scan: the latest that has its airport summary (as hub_progress() reads it)
  select jsonb_build_object('taken_at', private.fig_ts(s.taken_at), 'week', s.week, 'status', s.status)
    into v_scan
    from public.game_scans s
   where s.world_id = w and s.taken_at <= v_at and exists (select 1 from public.scan_airline_airports x where x.scan_id = s.id)
   order by s.taken_at desc, s.id desc limit 1;

  -- usage the database can measure, each against its trigger (manual §1; #16, #17, #20): now, whatever the moment
  v_db := pg_database_size(current_database());
  select coalesce(sum(octet_length(r.pdf_b64)), 0) * 3 / 4 into v_pdf from public.site_reports r where r.pdf_b64 is not null;
  v_site := octet_length(public.site_public()::text);

  return jsonb_build_object(
    'world_id', w, 'as_of', private.fig_ts(v_at),
    'capture', private.fig_capture_status(w, v_at) -> 'airlines',
    'snapshot', coalesce(v_snap, '{}'::jsonb) || jsonb_build_object('last_run', v_job, 'fallback_at', private.fig_ts(v_fb)),
    'backup', jsonb_build_object('last', v_backup, 'last_good', v_good),
    'archive', v_arch,
    'cleanup', v_clean,
    'scan', v_scan,
    'usage', jsonb_build_array(
      jsonb_build_object('key', 'database', 'label', 'Database size', 'bytes', v_db, 'trigger_bytes', 350 * 1024 * 1024::bigint),
      jsonb_build_object('key', 'report_pdfs', 'label', 'Report PDFs', 'bytes', v_pdf, 'trigger_bytes', 50 * 1024 * 1024::bigint),
      jsonb_build_object('key', 'site_public', 'label', 'The website''s data', 'bytes', v_site, 'trigger_bytes', 500 * 1024::bigint)));
end
$function$;

-- ---------------------------------------------------------------- who may run what
revoke all on function private.capture_statement_lines(jsonb), private.capture_expect(bigint),
  private.capture_judge(text, integer, text, boolean, jsonb, numeric, numeric), private.capture_check(bigint, jsonb, jsonb),
  private.capture_airline_verdict(bigint, timestamptz), private.capture_panel_words(jsonb)
  from public, anon, authenticated, service_role;
revoke all on function public.system_status(bigint, timestamptz) from public, anon, authenticated, service_role;
grant execute on function public.system_status(bigint, timestamptz) to authenticated;

-- ---------------------------------------------------------------- descriptions (decision #10)
comment on column public.game_capture_raw.verdict is 'The page''s check as it arrived (#21): ok, short (fewer rows than expected) or broken (didn''t read, or a balance sheet without the cash account); null for page inspection (html) and pages stored before 14 Oct''s checks';
comment on column public.game_capture_raw.verdict_note is 'The verdict in words: what was expected and what came, e.g. loads 12 of 78 flights (#21)';
comment on column public.game_capture_raw.verdict_facts is 'The numbers behind the verdict (#21): read (rows the reader took), and per kind scheduled and share (loads), median_lines and nights (statement), cash (balance), the limit used, or the error';
comment on table public.game_capture_raw is 'Every page the capture sent, as rows of cells before parsing, with its world and airline, and its check as it arrived (verdict, #21). Kept 14 days: the 10:20 UTC clean-up (private.job_cleanup, #13 pull request 7) deletes older pages. Written by capture_ingest(). Read by private.capture_page(), completeness (private.capture_day_complete), capture_status() and system_status() (each airline''s latest verdicts) and the planner''s Capture board.';
comment on function private.capture_statement_lines(jsonb) is 'The lines a bank statement page holds, as the reader takes them: rows whose first filled cell is a date and time (DD.MM. HH:MI). The recent nights a statement page is checked against are counted with it (#21).';
comment on function private.capture_expect(bigint) is 'What to expect of one stored capture page, from what the database knows at the page''s moment (#21). Loads: scheduled, the airline''s flights departing in the page''s window (the game''s -24h: the 24 hours before the capture), from its flight legs and their UTC weekdays, each rotation from the day after it launched (an aircraft''s first day is rarely flown in full). Statement: median_lines, the median of the lines on the airline''s latest statement page on each of up to 7 earlier capture days, and nights, how many. Other kinds: nothing.';
comment on function private.capture_judge(text, integer, text, boolean, jsonb, numeric, numeric) is 'The verdict on one capture page (#21), from what was read and what was expected; reads no table. Broken: the page didn''t read (p_error), or a balance sheet without the cash account (2800). Short: loads fewer than p_loads_min of the flights scheduled; a statement with no lines, or fewer than p_statement_min of the recent median; events or an income statement with no rows. Otherwise ok. Answers {verdict, note (in words), facts}; null for a kind it doesn''t judge (html).';
comment on function private.capture_check(bigint, jsonb, jsonb) is 'Judges one stored capture page and keeps the verdict on it (game_capture_raw.verdict, verdict_note, verdict_facts; #21). p_parse is private.capture_page()''s answer (its rows read) or the parse error; p_expect what to expect (private.capture_expect() when null; the tests give their own). The limits are settings: capture_loads_min_share and capture_statement_min_share. Answers the verdict with its facts; null for page inspection (html).';
comment on function private.capture_airline_verdict(bigint, timestamptz) is 'An airline''s capture as at a moment (#21): the latest page of each kind in that moment''s capture day (10:00 to 10:00 UTC) up to the moment, with its verdict, and the airline''s verdict: broken if any page is, short if any is or a kind wasn''t captured, ok when every page is; null when no page was judged (stored before the checks). words: "all good", or what came in short or broken.';
comment on function private.capture_panel_words(jsonb) is 'The capture panel''s words after an airline''s loads page (#21): what was read, then one line for the airline: "all good", or what came in short or broken, ending on the loads as "12 of 78" because the userscript adds " flights". capture_ingest() puts them in its reply''s rows, so the userscript needs no change.';
comment on function private.capture_store(bigint, text, text, text, jsonb, timestamptz, boolean) is 'Stores one page for an airline of the given world and parses it, at the given capture time, checks it (private.capture_check(), #21: its verdict kept on the raw page and given under verdict; after the loads page, the airline''s capture as it stands under airline_verdict), and says whether that capture day is now complete. When the page completes the world''s capture for the day (private.snapshot_due), takes the daily snapshot (private.take_snapshot, one job_runs row, ok or failed; a failure never loses the page) and answers with it under snapshot. Refuses a page for an airline outside the world. capture_ingest() calls it with now(); the tests replay saved pages with their own times. p_loads_step is no longer used: the old planner''s loads step went with the clean-up (build pull request 14).';
comment on function public.capture_ingest(text, text, text, text, jsonb) is 'Entry point for the in-game capture. Checks the capture key, which belongs to one world; finds the airline by the game''s ID or, from older userscripts, by name, and refuses one outside the key''s world; keeps the raw page (the 10:20 UTC clean-up deletes it after 14 days), parses it (private.capture_store, private.capture_page): bank statement into game_flights and game_payments, loads into game_flights; and checks it (#21: the verdict under verdict). After the loads page, rows holds the capture panel''s words (what was read, and the airline''s verdict: "all good" or what came in short or broken) and count the rows read. Answers with the capture day and whether it is complete; the page that completes the world''s capture for the day also takes the daily snapshot (airline_days, route_days) and answers with it.';
comment on function private.fig_capture_status(bigint, timestamptz) is 'The captured figures (#19): the capture board''s document (captureBoard), each airline''s pages today and yesterday (UTC), flights by departure date, what is missing today and its status; since #21 also its latest page (last_at) and that capture''s verdicts (private.capture_airline_verdict(): verdict, verdict_words, verdict_at, verdict_day and each kind''s under verdicts). See capture_status().';
comment on function public.system_status(bigint, timestamptz) is 'The Systems board on the planner''s Check screen (#23), read only, as of p_as_of (now by default) in a world (the default when null): capture, each airline''s latest page and verdicts (capture_status()''s airlines); snapshot, the latest day in airline_days with how it was taken (source capture, or fallback and so incomplete), the latest snapshot job and when the 10:00 UTC job last ran; backup, its latest run and latest good copy (restore check passed) with its size; archive, its runs this month, its latest run and any table and month whose latest run failed; cleanup, its latest run; scan, the latest world scan with its airport summary; usage, the database''s size, the report PDFs in site_reports (three quarters of their base64 text) and the size of site_public(), each with its trigger (manual §1: 350 MB, 50 MB, 500 KB), measured now. The board marks them. Staff only; runs as owner.';

select set_config('equinox.actor', '', true), set_config('equinox.actor_detail', '', true);

-- Capture page checks (decision #21): a loads page expects only the flights of aircraft that have flown. A fix to
-- 20261014220000_capture_checks.sql, found the morning after it was applied (15 Oct).
--
-- Why: on 15 Oct the last capture's loads pages would have been judged short for China Eastern (80 of 104), Malaysia
-- (61 of 80) and Virgin (83 of 110). Every missing flight belonged to an aircraft filed on 13 Oct that hadn't flown yet
-- (Malaysia's 9M-AAK to 9M-AAO, 20 legs, none with loads); every aircraft that had flown was complete. Counting a
-- rotation from the day after it launched wasn't enough: a new aircraft can start flying days after it's filed.
-- With this rule the same pages expect 78, 60 and 82, and all six airlines are judged ok.
--
-- Replaces one function with the same arguments, and corrects one setting's description; takes nothing away, so it can
-- be applied from the chat:
--   private.capture_expect(): a leg with an aircraft counts only once that aircraft has flown (its registration named
--     by the airline's captured loads before the page); a leg with no aircraft counts as before.
--   settings.capture_loads_min_share: its description says so.

select set_config('equinox.actor', 'migration', true),
       set_config('equinox.actor_detail', '20261015120000_capture_expect_flown', true);

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

comment on function private.capture_expect(bigint) is 'What to expect of one stored capture page, from what the database knows at the page''s moment (#21). Loads: scheduled, the airline''s flights departing in the page''s window (the game''s -24h: the 24 hours before the capture), from its flight legs and their UTC weekdays, each rotation from the day after it launched, and a leg with an aircraft only once that aircraft has flown (its registration named by the airline''s captured loads before the page; since 15 Oct, as a new aircraft can start flying days after it''s filed). Statement: median_lines, the median of the lines on the airline''s latest statement page on each of up to 7 earlier capture days, and nights, how many. Other kinds: nothing.';

update public.settings set description = 'Each loads page is checked as it arrives (#21): short when it reads fewer flights than this share of the airline''s flights scheduled in the page''s window (its flight legs departing in the 24 hours before the capture, each rotation from the day after it launched, and a leg with an aircraft only once that aircraft has flown)'
 where key = 'capture_loads_min_share' and airline_id is null;

select set_config('equinox.actor', '', true), set_config('equinox.actor_detail', '', true);

-- Interline: the day we sent each request (3 Nov 2026; manual §6, "requests unanswered for two weeks"; spec
-- docs/specs/2026-11-03-interline-replies.md, option A of the Building chat's brief, decided by Gitesh the same day).
--
-- Why: a request we send waits in interline_agreements with status to_sign, and the day it was sent lived only in the
-- free-text note ("Requested 2 Nov ...", "Request sent 3 Nov ..."). Nothing could count how long a request had waited, so
-- the Saturday review couldn't list the ones unanswered for two weeks without reading every note. 16 were waiting on 3 Nov.
--
-- Adds, changes, drops and renames nothing else, so it can be applied from the chat:
--   1. interline_agreements.requested_on date (null allowed), described. The table's grants (select, insert, update and
--      delete for authenticated, nothing for anon; migration 20261009210000) and its change-log trigger cover the new
--      column; planner_save() reads each table's columns from the catalogue, so it writes the column with no change.
--      The comment on status stays as it is, and no status is added.
--   2. It is filled for every to_sign row: the first "Requested <d> <Mon>" or "Request sent <d> <Mon>" in the note
--      (year 2026), else the row's decided_on, else created_at's UTC date. Logged as actor claude, detail
--      "building interline replies" (not with logging off).
--   3. settings.interline_reply_wait_days: 14 days, world-level in every world (airline null), described. It reaches the
--      planner through rules_input(), which carries every world setting as it is (no function changes); Interline's
--      Waiting for a reply board marks a request at or over it, and Reference -> constants shows it.

select set_config('equinox.actor', 'claude', true), set_config('equinox.actor_detail', 'building interline replies', true);

alter table public.interline_agreements add column requested_on date;

comment on column public.interline_agreements.requested_on is
  'The day we sent the request; set while the row waits on the other airline (status to_sign). The planner sets it to the '
  'UTC date when a row becomes to_sign without one, and it can be changed by hand. Kept as history when the status moves '
  'on. Interline''s Waiting for a reply board counts the days from it against settings.interline_reply_wait_days '
  '(manual §6). Filled for the rows waiting on 3 Nov 2026 from their notes (migration 20261103010000).';

-- the note's first "Requested 2 Nov" or "Request sent 3 Nov" (either way round, any case), as a 2026 date; a day the month
-- doesn't have (31 Nov) counts as no date in the note
with
waiting as (
  select i.id, i.decided_on, i.created_at,
         regexp_match(coalesce(i.note, ''), '(?:requested|request sent)\s+(\d{1,2})\s+([a-z]{3})', 'i') as m
    from public.interline_agreements i
   where i.status = 'to_sign' and i.requested_on is null),
parsed as (
  select w.id, w.decided_on, w.created_at, (w.m)[1]::int as d,
         array_position(array['jan','feb','mar','apr','may','jun','jul','aug','sep','oct','nov','dec'], lower((w.m)[2])) as mo
    from waiting w),
noted as (
  select p.id, p.decided_on, p.created_at,
         case when p.mo is not null and p.d between 1 and 31
                   and extract(month from make_date(2026, p.mo, 1) + (p.d - 1)) = p.mo
              then make_date(2026, p.mo, 1) + (p.d - 1) end as note_day
    from parsed p)
update public.interline_agreements i
   set requested_on = coalesce(n.note_day, n.decided_on, (n.created_at at time zone 'UTC')::date)
  from noted n
 where n.id = i.id;

insert into public.settings (world_id, airline_id, key, value, unit, description, since, reason)
select w.id, null, 'interline_reply_wait_days', '14'::jsonb, 'days',
       'How long a request we sent may wait for a reply (manual §6: the Saturday review lists requests unanswered for two '
       'weeks; the player may be inactive, so withdraw and ask the next-best airline at that airport, or leave it if there '
       'is none). Interline''s Waiting for a reply board marks a to_sign row whose requested_on is this many days back or '
       'more. Shown under Reference -> constants.',
       date '2026-11-03', 'Gitesh, 3 Nov: option A of the Building chat''s brief (spec docs/specs/2026-11-03-interline-replies.md), built to match manual §6''s two-week check'
  from public.worlds w
on conflict on constraint settings_world_airline_key_key do nothing;

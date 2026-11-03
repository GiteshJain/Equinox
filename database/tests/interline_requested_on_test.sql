-- Interline: the day we sent each request (manual §6; migration 20261103010000; spec
-- docs/specs/2026-11-03-interline-replies.md). Run by database/rehearse.sh on the copy of last night's backup, after the
-- new migrations, inside a transaction that is rolled back. A failed check stops with an error that says which (ids and
-- counts, never notes).
--   1. interline_agreements.requested_on: a date, null allowed, described; status's comment unchanged.
--   2. The fill, checked exactly on the night the migration runs (database/tests/before/interline_requested_on_before.sql
--      saw no requested_on before the changes): no to_sign row with a partner is left without requested_on (none at all,
--      partner or not); where the note names the day ("Requested 2 Nov", "Request sent 3 Nov"), that day (2026) is the
--      row's, read here a second way (to_date) rather than with the migration's expression; a to_sign row with no such
--      note has its decided_on, else created_at's UTC date; rows with another status were left alone (null). The fill is
--      logged as actor claude. On later nights the planner has been writing the column (a row that moved on keeps its day
--      as history, a day can be cleared by hand), so only the count of to_sign rows without one is printed.
--   3. interline_reply_wait_days: a world-level setting in every world, in days, described with manual §6, since and
--      reason; 14 in the default world, no airline's own; rules_input() carries it.
--   4. planner_save() writes the column: as staff, an insert with requested_on and an update of it read back.

create temporary table t_ir (k text primary key, v jsonb) on commit drop;
grant select, insert, update on t_ir to authenticated, anon;
insert into public.planner_users (email) values ('interline-replies-staff@example.com') on conflict do nothing;

-- the note's first "Requested <d> <Mon>" or "Request sent <d> <Mon>" as a 2026 date, read with to_date(); none when there
-- is none or the day isn't one the month has
create function pg_temp.ir_note_day(p_note text) returns date language plpgsql immutable as $f$
declare x text[] := regexp_match(coalesce(p_note, ''), '(?:requested|request sent)\s+(\d{1,2})\s+([a-z]{3})', 'i'); v date;
begin
  if x is null then return null; end if;
  v := to_date(lpad(x[1], 2, '0') || ' ' || initcap(x[2]) || ' 2026', 'DD Mon YYYY');
  -- to_date() lets 31 Nov roll on in some versions: only a day that reads back the same counts
  return case when extract(day from v) = x[1]::int then v end;
exception when others then
  return null;
end
$f$;

-- ---------------------------------------------------------------- 1. the column
do $test$
begin
  assert (select format_type(a.atttypid, a.atttypmod) = 'date' and not a.attnotnull
            from pg_attribute a where a.attrelid = 'public.interline_agreements'::regclass and a.attname = 'requested_on' and not a.attisdropped),
    'interline_agreements.requested_on isn''t a date that allows null';
  assert col_description('public.interline_agreements'::regclass,
                         (select attnum from pg_attribute where attrelid = 'public.interline_agreements'::regclass and attname = 'requested_on'))
         ilike '%to_sign%', 'interline_agreements.requested_on has no description (naming to_sign)';
  assert col_description('public.interline_agreements'::regclass,
                         (select attnum from pg_attribute where attrelid = 'public.interline_agreements'::regclass and attname = 'status'))
         = 'to_sign, signed, declined or nopartner; empty = not contacted yet (the planner''s record has no status)',
    'the comment on interline_agreements.status changed';
end
$test$;

-- ---------------------------------------------------------------- 2. the fill
do $test$
declare bad text; n_wait int; n_partner int; n_note int; n_fallback int; n_logged int;
begin
  select count(*), count(*) filter (where i.partner is not null) into n_wait, n_partner
    from public.interline_agreements i where i.status = 'to_sign';
  if to_regclass('rehearsal_before.interline_requested_on') is null
     or coalesce((select b.had_column from rehearsal_before.interline_requested_on b limit 1), true) then
    raise notice 'requested_on was there before the changes: the fill ran on an earlier night; % to_sign rows, % without requested_on',
      n_wait, (select count(*) from public.interline_agreements i where i.status = 'to_sign' and i.requested_on is null);
    return;
  end if;
  select string_agg(i.id::text, ', ') into bad from public.interline_agreements i
   where i.status = 'to_sign' and i.partner is not null and i.requested_on is null;
  assert bad is null, 'to_sign rows with a partner left without requested_on: ' || bad;
  select string_agg(i.id::text, ', ') into bad from public.interline_agreements i where i.status = 'to_sign' and i.requested_on is null;
  assert bad is null, 'to_sign rows left without requested_on: ' || bad;

  -- the note's day, read a second way (pg_temp.ir_note_day(), above: to_date(), with a day the month lacks as none)
  with d as (
    select i.id, i.requested_on, i.decided_on, i.created_at, pg_temp.ir_note_day(i.note) as note_day
      from public.interline_agreements i where i.status = 'to_sign')
  select string_agg(d.id::text, ', ') filter (where d.requested_on is distinct from coalesce(d.note_day, d.decided_on, (d.created_at at time zone 'UTC')::date)),
         count(*) filter (where d.note_day is not null), count(*) filter (where d.note_day is null)
    into bad, n_note, n_fallback
    from d;
  assert bad is null, 'to_sign rows whose requested_on isn''t the note''s day (else decided_on, else created_at''s UTC date): ' || bad;

  -- other statuses: the fill left them alone
  select string_agg(i.id::text, ', ') into bad from public.interline_agreements i
   where i.status is distinct from 'to_sign' and i.requested_on is not null;
  assert bad is null, 'rows with another status were given requested_on by the fill: ' || bad;

  select count(*) into n_logged from public.change_log l
   where l.table_name = 'interline_agreements' and l.op = 'update' and l.actor = 'claude'
     and l.actor_detail = 'building interline replies' and l.new_values ? 'requested_on';
  assert n_logged = n_wait, format('the fill logged %s rows as claude (building interline replies), %s are waiting', n_logged, n_wait);
  raise notice 'requested_on: % to_sign rows (% with a partner), every one filled: % from the note, % from decided_on or created_at; % logged as claude',
    n_wait, n_partner, n_note, n_fallback, n_logged;
end
$test$;

-- ---------------------------------------------------------------- 3. the setting
do $test$
declare dw bigint := (select id from public.worlds where is_default); d jsonb;
begin
  assert not exists (select 1 from public.worlds x
                      where not exists (select 1 from public.settings s where s.world_id = x.id and s.airline_id is null
                                           and s.key = 'interline_reply_wait_days' and s.unit = 'days' and s.description ilike '%manual §6%'
                                           and s.since is not null and s.reason is not null)),
    'a world has no described interline_reply_wait_days setting in days (naming manual §6, with since and reason)';
  assert (select s.value from public.settings s where s.world_id = dw and s.airline_id is null and s.key = 'interline_reply_wait_days') = '14'::jsonb,
    'interline_reply_wait_days isn''t 14 in the default world';
  assert not exists (select 1 from public.settings s where s.key = 'interline_reply_wait_days' and s.airline_id is not null),
    'an airline has its own interline_reply_wait_days';
  d := public.rules_input(dw, 'all');
  assert d #> '{settings,interline_reply_wait_days}' = '14'::jsonb, 'rules_input() doesn''t carry interline_reply_wait_days as 14';
  raise notice 'interline_reply_wait_days: 14 days in every world, described, no airline''s own; rules_input() carries it';
end
$test$;

-- ---------------------------------------------------------------- 4. planner_save() writes it
-- an airline of the default world and a country it has no agreement for (a test row, rolled back with the rest)
do $test$
declare w bigint := (select id from public.worlds where is_default); al bigint; cc text;
begin
  select a.id into al from public.airlines a where a.world_id = w order by a.id limit 1;
  assert al is not null, 'the default world has no airline';
  select c.code into cc from public.countries c
   where not exists (select 1 from public.interline_agreements i where i.airline_id = al and i.country_code = c.code)
   order by c.code limit 1;
  assert cc is not null, 'no country is free for the test row';
  insert into t_ir values ('world', to_jsonb(w)), ('airline', to_jsonb(al)), ('country', to_jsonb(cc));
end
$test$;

do $$ begin perform set_config('request.jwt.claims',
  '{"sub": "00000000-0000-4000-8000-0000000000f3", "email": "interline-replies-staff@example.com", "role": "authenticated"}', true); end $$;
set local role authenticated;
do $test$
declare r jsonb; v_id bigint; v_base text;
  w bigint := (select (v #>> '{}')::bigint from t_ir where k = 'world');
  al bigint := (select (v #>> '{}')::bigint from t_ir where k = 'airline');
  cc text := (select v #>> '{}' from t_ir where k = 'country');
begin
  r := public.planner_save(jsonb_build_array(jsonb_build_object('table', 'interline_agreements', 'op', 'insert',
         'values', jsonb_build_object('world_id', w, 'airline_id', al, 'country_code', cc, 'status', 'to_sign',
                                      'partner', 'interline replies test', 'requested_on', '2026-11-03'))), 'interline-replies-test');
  assert (r ->> 'ok')::boolean, 'planner_save() didn''t insert a row with requested_on: ' || coalesce(r::text, 'no answer');
  v_id := (r #>> '{rows,0,key,id}')::bigint;
  v_base := r #>> '{rows,0,updated_at}';
  insert into t_ir values ('id', to_jsonb(v_id));
  r := public.planner_save(jsonb_build_array(jsonb_build_object('table', 'interline_agreements', 'op', 'update', 'key', jsonb_build_object('id', v_id),
         'base', v_base, 'values', jsonb_build_object('requested_on', '2026-11-01'))), 'interline-replies-test');
  -- within one transaction now() doesn't move, so the update may clash on its own insert's updated_at; then it says so
  assert (r ->> 'ok')::boolean or r ? 'clashes', 'planner_save() refused an update of requested_on: ' || coalesce(r::text, 'no answer');
  insert into t_ir values ('updated', to_jsonb((r ->> 'ok')::boolean));
end
$test$;
reset role;
do $test$
declare v_id bigint := (select (v #>> '{}')::bigint from t_ir where k = 'id');
  upd boolean := (select (v #>> '{}')::boolean from t_ir where k = 'updated');
begin
  assert exists (select 1 from public.interline_agreements i where i.id = v_id and i.status = 'to_sign'
                   and i.requested_on = case when upd then date '2026-11-01' else date '2026-11-03' end),
    'the row planner_save() wrote doesn''t read back with its requested_on';
  assert exists (select 1 from public.change_log l where l.table_name = 'interline_agreements' and l.row_key = jsonb_build_object('id', v_id)
                   and l.op = 'insert' and l.actor = 'planner' and l.new_values ->> 'requested_on' = '2026-11-03'),
    'the insert isn''t logged as planner with its requested_on';
  raise notice 'planner_save() writes requested_on (insert read back%)', case when upd then ', update read back' else '; the update clashed inside the one transaction' end;
end
$test$;

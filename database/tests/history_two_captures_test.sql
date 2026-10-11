-- Two captures on one UTC date (#13 build, pull request 6; the bug pull request 3 found): game_balance and game_pnl kept
-- the first capture's captured_at while a second capture the same UTC date overwrote the figures. Run by
-- database/rehearse.sh on the copy of last night's backup, after the new migrations, inside a transaction that is rolled
-- back. A failed check stops with an error that says which.
--   1. Hand-made pages for one airline on one UTC date (in 2099, so nothing real is touched), through the capture's own
--      path (private.capture_store): a balance sheet and an income statement at 01:00, then others at 03:00 with other
--      figures. The second capture's figures and its time both win, and its capture day; capture_cash gives the second
--      capture's cash, timed by it, with the payments due in the 7 days after it (one due between the two captures is
--      left out); the daily history (private.take_snapshot) takes the same. A page from 02:00 sent after them changes
--      nothing: the latest capture wins whatever the order.
--   2. On the copy: every balance-sheet and income-statement row that a kept page holds carries the figures and the time
--      of one page, the latest that holds it (the migration repaired those the old rule left with the first capture's
--      time; their figures didn't change).

do $test$
declare w bigint := (select id from public.worlds where is_default); kf bigint; r jsonb; b record; p record; c record; d record;
begin
  select id into kf from public.airlines where world_id = w and game_id = 113;
  -- payments ahead: one due between the two captures, one after the second
  insert into public.game_events (world_id, airline_id, airline, event_date, event_time, descr, debit, captured_at, due_at)
  values (w, kf, 'Kingfisher', '2099-06-01', '02:00', 'History test: due between the captures', 111, '2099-06-01 01:00+00', '2099-06-01 02:00+00'),
         (w, kf, 'Kingfisher', '2099-06-02', '12:00', 'History test: due after both', 222, '2099-06-01 01:00+00', '2099-06-02 12:00+00');

  -- the first capture, 01:00 UTC on 1 Jun (the evening of 31 May)
  r := private.capture_store(w, '113', 'balance', '/test', '[["2800", "Bank", "1,000,000 AS$", "3000", "Equity", "5 AS$"]]', '2099-06-01 01:00+00');
  assert r ->> 'ok' = 'true', 'the first balance sheet wasn''t taken: ' || r::text;
  r := private.capture_store(w, '113', 'pnl', '/test', '[["History test line", "100 AS$", "90 AS$", "1,000 AS$"]]', '2099-06-01 01:00+00');
  assert r ->> 'ok' = 'true', 'the first income statement wasn''t taken: ' || r::text;
  -- the second, 03:00 UTC the same UTC date, other figures
  r := private.capture_store(w, '113', 'balance', '/test', '[["2800", "Bank", "2,000,000 AS$", "3000", "Equity", "6 AS$"]]', '2099-06-01 03:00+00');
  assert r ->> 'ok' = 'true', 'the second balance sheet wasn''t taken: ' || r::text;
  r := private.capture_store(w, '113', 'pnl', '/test', '[["History test line", "200 AS$", "190 AS$", "2,000 AS$"]]', '2099-06-01 03:00+00');
  assert r ->> 'ok' = 'true', 'the second income statement wasn''t taken: ' || r::text;

  select * into b from public.game_balance where airline_id = kf and captured_on = '2099-06-01' and account = '2800 Bank';
  assert b.amount = 2000000 and b.captured_at = '2099-06-01 03:00+00' and b.capture_day = '2099-05-31',
    format('the balance sheet after two captures: %s at %s (capture day %s), expected the second''s 2000000 at 03:00 (31 May)', b.amount, b.captured_at, b.capture_day);
  select * into b from public.game_balance where airline_id = kf and captured_on = '2099-06-01' and account = '3000 Equity';
  assert b.amount = 6 and b.captured_at = '2099-06-01 03:00+00', 'the second account didn''t take the second capture''s figure and time';
  select * into p from public.game_pnl where airline_id = kf and captured_on = '2099-06-01' and line = 'History test line';
  assert (p.current_p, p.last_p, p.total_p) = (200, 190, 2000) and p.captured_at = '2099-06-01 03:00+00' and p.capture_day = '2099-05-31',
    format('the income statement after two captures: %s/%s/%s at %s, expected the second''s 200/190/2000 at 03:00', p.current_p, p.last_p, p.total_p, p.captured_at);

  -- capture_cash and the cash forecast's figures: the latest capture's cash, timed by it
  select * into c from public.capture_cash where airline_id = kf and day = '2099-06-01';
  assert c.cash = 2000000 and c.cash_at = '2099-06-01 03:00+00' and c.fixed_next7 = 222,
    format('capture_cash after two captures: %s at %s, next 7 days %s; expected 2000000 at 03:00 and 222 (the payment due between the captures left out)', c.cash, c.cash_at, c.fixed_next7);

  -- a page from between them, sent late, changes nothing
  r := private.capture_store(w, '113', 'balance', '/test', '[["2800", "Bank", "1,500,000 AS$", "3000", "Equity", "7 AS$"]]', '2099-06-01 02:00+00');
  r := private.capture_store(w, '113', 'pnl', '/test', '[["History test line", "150 AS$", "140 AS$", "1,500 AS$"]]', '2099-06-01 02:00+00');
  select * into b from public.game_balance where airline_id = kf and captured_on = '2099-06-01' and account = '2800 Bank';
  assert b.amount = 2000000 and b.captured_at = '2099-06-01 03:00+00', 'an older page sent late overwrote the newer capture''s balance';
  select * into p from public.game_pnl where airline_id = kf and captured_on = '2099-06-01' and line = 'History test line';
  assert p.current_p = 200 and p.captured_at = '2099-06-01 03:00+00', 'an older page sent late overwrote the newer capture''s income statement';

  -- the daily history takes the same
  perform private.take_snapshot(w, '2099-05-31', '2099-06-01 04:00+00', 'capture');
  select * into d from public.airline_days where airline_id = kf and day = '2099-05-31';
  assert d.cash = 2000000 and d.cash_at = '2099-06-01 03:00+00' and d.fixed_next7 = 222,
    format('the daily history took %s at %s (next 7 days %s), not the latest capture', d.cash, d.cash_at, d.fixed_next7);
  raise notice 'two captures on one UTC date: the second''s figures and time win in game_balance, game_pnl, capture_cash and airline_days; a page sent late changes nothing';
end
$test$;

-- ---------------------------------------------------------------- 2. on the copy
do $test$
declare n_rows bigint; bad bigint; n_moved bigint; n_changed bigint; n_rows_p bigint; bad_p bigint; n_moved_p bigint;
begin
  -- every row a kept page holds: its figure and time are those of the latest page that holds it
  with pages as (
    select r.airline_id, r.captured_at, (r.captured_at at time zone 'UTC')::date as d, x.account, x.amount
      from public.game_capture_raw r
      cross join lateral jsonb_array_elements(case when jsonb_typeof(r.rows) = 'array' then r.rows else '[]'::jsonb end) e(row_)
      cross join lateral (select array(select jsonb_array_elements_text(case when jsonb_typeof(e.row_) = 'array' then e.row_ else '[]'::jsonb end)) as c) cc
      cross join lateral (values
        (case when array_length(cc.c, 1) >= 3 and cc.c[1] ~ '^\d{3,4}$' then cc.c[1] || ' ' || cc.c[2] end, public.as_num(cc.c[3])),
        (case when array_length(cc.c, 1) >= 6 and cc.c[4] ~ '^\d{3,4}$' then cc.c[4] || ' ' || cc.c[5] end, public.as_num(cc.c[6]))) x(account, amount)
     where r.kind = 'balance' and x.account is not null and r.captured_at < '2099-01-01'),
  latest as (select distinct on (airline_id, d, account) * from pages order by airline_id, d, account, captured_at desc)
  select count(*), count(*) filter (where (l.amount, l.captured_at) is distinct from (b.amount, b.captured_at))
    into n_rows, bad
    from public.game_balance b join latest l on l.airline_id = b.airline_id and l.d = b.captured_on and l.account = b.account;
  assert bad = 0, format('%s of the %s balance-sheet rows kept pages hold don''t carry the figure and time of the latest page that holds them', bad, n_rows);
  with pages as (
    select r.airline_id, r.captured_at, (r.captured_at at time zone 'UTC')::date as d, cc.c[1] as line,
           public.as_num(cc.c[2]) as current_p, public.as_num(cc.c[3]) as last_p, public.as_num(cc.c[array_length(cc.c, 1)]) as total_p
      from public.game_capture_raw r
      cross join lateral jsonb_array_elements(case when jsonb_typeof(r.rows) = 'array' then r.rows else '[]'::jsonb end) e(row_)
      cross join lateral (select array(select jsonb_array_elements_text(case when jsonb_typeof(e.row_) = 'array' then e.row_ else '[]'::jsonb end)) as c) cc
     where r.kind = 'pnl' and array_length(cc.c, 1) >= 3 and cc.c[2] ~ 'AS\$' and r.captured_at < '2099-01-01'),
  latest as (select distinct on (airline_id, d, line) * from pages order by airline_id, d, line, captured_at desc)
  select count(*), count(*) filter (where (l.current_p, l.last_p, l.total_p, l.captured_at) is distinct from (g.current_p, g.last_p, g.total_p, g.captured_at))
    into n_rows_p, bad_p
    from public.game_pnl g join latest l on l.airline_id = g.airline_id and l.d = g.captured_on and l.line = g.line;
  assert bad_p = 0, format('%s of the %s income-statement rows kept pages hold don''t carry the figures and time of the latest page that holds them', bad_p, n_rows_p);

  -- what the migration moved: times only, never figures
  if to_regclass('rehearsal_before.game_balance_times') is not null then
    select count(*) filter (where b.captured_at is distinct from o.captured_at), count(*) filter (where b.amount is distinct from o.amount)
      into n_moved, n_changed
      from rehearsal_before.game_balance_times o join public.game_balance b using (airline, captured_on, account);
    assert n_changed = 0, format('%s balance-sheet figures changed', n_changed);
    select count(*) filter (where g.captured_at is distinct from o.captured_at),
           count(*) filter (where (g.current_p, g.last_p, g.total_p) is distinct from (o.current_p, o.last_p, o.total_p))
      into n_moved_p, n_changed
      from rehearsal_before.game_pnl_times o join public.game_pnl g using (airline, captured_on, line);
    assert n_changed = 0, format('%s income-statement figures changed', n_changed);
  end if;
  raise notice 'on the copy: all % balance-sheet and % income-statement rows that kept pages hold carry the figures and time of the latest page holding them (% and % rows got their own capture''s time; no figure changed)',
    n_rows, n_rows_p, coalesce(n_moved::text, '?'), coalesce(n_moved_p::text, '?');
end
$test$;

do $$ begin raise notice 'two captures on one UTC date: all checks passed'; end $$;

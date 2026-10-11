-- The daily snapshot on a complete capture (#13 build, pull request 6; design §7). Run by database/rehearse.sh on the
-- copy of last night's backup, after the new migrations, inside a transaction that is rolled back. A failed check stops
-- with an error that says which (dates, airlines and counts, never figures).
--   1. Through capture_ingest(), signed out like the userscript, with a test key: every active airline of ours sends its
--      five pages for today's capture day (emptied first); only the very last page answers with a snapshot.
--   2. The copy's last complete evening, replayed page by page at the pages' own times through the capture's path
--      (private.capture_store), after its pages and its history day are taken out: exactly one snapshot, taken by the
--      page that completes the evening (the last airline's last page, worked out here independently), none before.
--      The day's row for each airline is then from the capture: complete, its point-in-time figures as at that page
--      (cash: the evening's latest balance up to it), the flows of that UTC day and the two before recomputed, and one
--      job_runs row.
--   3. The same evening captured again (the same pages a minute after the last, with other cash): one more snapshot, at
--      its last page, which replaces the point-in-time figures (cash, its time, taken_at). A backfill or fallback
--      afterwards replaces nothing.
--   4. How long a snapshot takes on the copy (best of 3).

create temporary table t_s (k text primary key, v text) on commit drop;
grant select on t_s to anon;

-- ---------------------------------------------------------------- 1. through capture_ingest(), signed out
do $setup$
declare w bigint := (select id from public.worlds where is_default); d date;
begin
  insert into public.capture_keys (label, key_hash, world_id)
  values ('history test', extensions.crypt('history-test-key', extensions.gen_salt('bf')), w);
  d := private.capture_day(w, now());
  delete from public.game_capture_raw where world_id = w and captured_at >= private.capture_day_start(w, d)
                                         and captured_at < private.capture_day_start(w, d) + interval '1 day';
  delete from public.airline_days where world_id = w and day = d;
  insert into t_s values ('world', w::text), ('today', d::text),
    ('pages', (select string_agg(a.game_id::text || ':' || k.kind, ',' order by a.position nulls last, a.id, k.o)
                 from public.airlines a join public.groups g on g.id = a.group_id and g.world_id = a.world_id
                 cross join (values (1, 'events'), (2, 'statement'), (3, 'pnl'), (4, 'balance'), (5, 'loads')) k (o, kind)
                where a.world_id = w and a.active and g.kind = 'ours'));
end
$setup$;
set local role anon;
do $test$
declare pg text; r jsonb; n int := 0; total int; v_snap_at int;
begin
  total := cardinality(string_to_array((select v from t_s where k = 'pages'), ','));
  foreach pg in array string_to_array((select v from t_s where k = 'pages'), ',') loop
    n := n + 1;
    r := public.capture_ingest('history-test-key', split_part(pg, ':', 1), split_part(pg, ':', 2), '/history-test', '[]');
    assert r ->> 'ok' = 'true', format('page %s of %s wasn''t taken: %s', n, total, r ->> 'error');
    if r ? 'snapshot' then
      assert v_snap_at is null, format('a second snapshot at page %s', n);
      v_snap_at := n;
      assert r #>> '{snapshot,ok}' is null and (r #>> '{snapshot,airlines}')::int > 0, 'the snapshot failed: ' || (r -> 'snapshot')::text;
    end if;
  end loop;
  assert v_snap_at = total, format('capture_ingest() took the snapshot at page %s of %s, expected the last', coalesce(v_snap_at::text, 'none'), total);
end
$test$;
reset role;
do $test$
declare w bigint := (select v::bigint from t_s where k = 'world'); d date := (select v::date from t_s where k = 'today'); n int;
begin
  select count(*) into n from public.airline_days where world_id = w and day = d and source = 'capture' and complete;
  assert n = (select count(*) from public.airlines a join public.groups g on g.id = a.group_id and g.world_id = a.world_id
               where a.world_id = w and a.active and g.kind = 'ours'),
    format('capture_ingest()''s snapshot wrote %s complete day(s) from the capture for today', n);
  assert exists (select 1 from public.job_runs j where j.job = 'snapshot' and j.status = 'ok' and j.for_day = d and j.world_id = w),
    'capture_ingest()''s snapshot wrote no job_runs row';
  raise notice 'capture_ingest(), signed out: % pages for today''s capture day, the snapshot taken by the last one only (% airlines)',
    cardinality(string_to_array((select v from t_s where k = 'pages'), ',')), n;
end
$test$;

-- ---------------------------------------------------------------- 2 and 3. the copy's last complete evening, replayed
-- each page's balance cash replaced (for the second capture): the cell after account 2800, in either pair of columns
create function pg_temp.with_cash(p_rows jsonb, p_amount numeric) returns jsonb language sql immutable as $f$
  select coalesce(jsonb_agg(case when jsonb_typeof(r) = 'array' and r ->> 0 ~ '^2800$' then jsonb_set(r, '{2}', to_jsonb(to_char(p_amount, 'FM999,999,999,990') || ' AS$'))
                                 when jsonb_typeof(r) = 'array' and r ->> 3 ~ '^2800$' then jsonb_set(r, '{5}', to_jsonb(to_char(p_amount, 'FM999,999,999,990') || ' AS$'))
                                 else r end order by o), '[]'::jsonb)
    from jsonb_array_elements(p_rows) with ordinality x(r, o)
$f$;

do $test$
declare
  w bigint := (select id from public.worlds where is_default);
  d date; v_from timestamptz; v_until timestamptz; v_ours bigint[]; pg record; r jsonb; v_expected bigint[] := '{}'; v_got bigint[] := '{}';
  v_seen text[] := '{}'; v_job bigint := coalesce((select max(id) from public.job_runs), 0); n int; bad text; v_t0 timestamptz;
  v_first_at timestamptz; v_second_at timestamptz; v_last_page timestamptz; v_pages int; v_rounds int; v_ms numeric; v_best numeric;
  v_shift interval;
begin
  select array_agg(a.id order by a.id) into v_ours
    from public.airlines a join public.groups g on g.id = a.group_id and g.world_id = a.world_id
   where a.world_id = w and a.active and g.kind = 'ours';
  -- the last capture day whose capture was complete, among the pages the copy keeps
  select max(x.d) into d
    from (select distinct private.capture_day(w, r.captured_at) as d from public.game_capture_raw r
           where r.world_id = w and r.captured_at < now() - interval '1 hour') x
   where private.capture_day_complete(w, x.d) and x.d < (select v::date from t_s where k = 'today');
  assert d is not null, 'the copy keeps no complete evening of capture pages';
  v_from := private.capture_day_start(w, d); v_until := v_from + interval '1 day';

  -- its pages, taken out, with its history day
  create temporary table t_pages on commit drop as
    select r.id, r.airline_id, a.game_id, r.kind, r.page_url, r.rows, r.captured_at
      from public.game_capture_raw r join public.airlines a on a.id = r.airline_id
     where r.world_id = w and r.captured_at >= v_from and r.captured_at < v_until and r.kind <> 'html';
  delete from public.game_capture_raw r where r.world_id = w and r.captured_at >= v_from and r.captured_at < v_until;
  delete from public.airline_days where world_id = w and day = d;
  select count(*) into v_pages from t_pages;

  -- where each complete capture ends, worked out here: the page at which every active airline of ours has all five
  -- pages since the last such page
  for pg in select * from t_pages order by captured_at, id loop
    if pg.airline_id = any (v_ours) and pg.kind in ('statement', 'events', 'pnl', 'balance', 'loads') then
      v_seen := array(select distinct x from unnest(v_seen || (pg.airline_id || ':' || pg.kind)) x);
      if (select bool_and((select count(*) from unnest(v_seen) s where split_part(s, ':', 1) = o::text) = 5) from unnest(v_ours) o) then
        v_expected := v_expected || pg.id; v_seen := '{}';
      end if;
    end if;
  end loop;
  v_rounds := cardinality(v_expected);
  assert v_rounds >= 1, 'the evening has no complete capture';

  -- 2. the replay, page by page at its own time
  for pg in select * from t_pages order by captured_at, id loop
    r := private.capture_store(w, pg.game_id::text, pg.kind, pg.page_url, pg.rows, pg.captured_at);
    if r ? 'snapshot' then
      assert r #>> '{snapshot,ok}' is null, 'the snapshot failed: ' || (r -> 'snapshot')::text;
      v_got := v_got || pg.id;
    end if;
  end loop;
  assert v_got = v_expected,
    format('the replay took snapshots at pages %s, expected at %s (the pages completing the evening''s capture)', v_got::text, v_expected::text);
  select t.captured_at into v_first_at from t_pages t where t.id = v_expected[cardinality(v_expected)];
  select max(t.captured_at) into v_last_page from t_pages t;

  -- the day's rows: from the capture, complete, as at the completing page
  select string_agg(al.planner_name, ', ') into bad
    from unnest(v_ours) o join public.airlines al on al.id = o
    left join public.airline_days x on x.airline_id = o and x.day = d
   where x.airline_id is null or x.source <> 'capture' or not x.complete or x.taken_at <> v_first_at
      or (x.cash, x.cash_at) is distinct from
         (select row(b.amount, b.captured_at) from public.game_balance b
           where b.airline_id = o and b.capture_day = d and b.account like '2800%' and b.amount is not null and b.captured_at <= v_first_at
           order by b.captured_at desc limit 1)
      or (x.aircraft_total, x.on_order) is distinct from (select row(f.aircraft_total, f.on_order) from private.history_fleet(w, v_first_at) f where f.airline_id = o)
      or x.weekly_departures is distinct from (select s.weekly_departures from private.history_schedule(w, d) s where s.airline_id = o);
  assert bad is null, 'the snapshot''s day isn''t from the complete capture, as at its last page, for: ' || bad;
  -- the flows of that UTC day and the two before, recomputed
  select string_agg(format('%s %s', x.airline_id, x.day), ', ') into bad
    from public.airline_days x
   where x.world_id = w and x.day between d - 2 and d
     and x.flights_flown is distinct from (select count(*)::int from public.game_flights f
                                            where f.airline_id = x.airline_id and (f.flight_no is not null or f.pax_income is not null)
                                              and coalesce((f.dep_at at time zone 'UTC')::date, f.game_date) = x.day);
  assert bad is null, 'the snapshot didn''t recompute the flows of its day and the two before for: ' || bad;
  select count(*) into n from public.job_runs j where j.id > v_job and j.job = 'snapshot';
  assert n = v_rounds and not exists (select 1 from public.job_runs j where j.id > v_job and j.job = 'snapshot' and (j.status <> 'ok' or j.for_day <> d)),
    format('the replay wrote %s snapshot job_runs row(s), expected %s, ok, for %s', n, v_rounds, d);
  raise notice 'the last complete evening (%), % pages replayed at their own times: % snapshot(s), each at the page completing the capture (the last at %), none before',
    d, v_pages, cardinality(v_got), to_char(v_first_at at time zone 'UTC', 'HH24:MI:SS');

  -- 3. a second complete capture the same evening: the same pages a minute after the last, other cash
  v_shift := (v_last_page + interval '1 minute') - (select min(captured_at) from t_pages);
  if v_last_page + interval '1 minute' + (select max(captured_at) - min(captured_at) from t_pages) >= v_until then
    v_shift := null;   -- no room left in the capture day: the pages go a second apart instead
  end if;
  v_got := '{}'; v_job := coalesce((select max(id) from public.job_runs), 0); n := 0;
  for pg in select t.*, row_number() over (order by t.captured_at, t.id) as o from t_pages t order by t.captured_at, t.id loop
    r := private.capture_store(w, pg.game_id::text, pg.kind, pg.page_url,
                               case when pg.kind = 'balance' then pg_temp.with_cash(pg.rows, 7000000 + pg.airline_id) else pg.rows end,
                               coalesce(pg.captured_at + v_shift, v_last_page + make_interval(secs => pg.o)));
    if r ? 'snapshot' then v_got := v_got || pg.id; v_second_at := coalesce(pg.captured_at + v_shift, v_last_page + make_interval(secs => pg.o)); end if;
  end loop;
  assert v_got = v_expected, format('the second capture took snapshots at pages %s, expected at %s', v_got::text, v_expected::text);
  select string_agg(al.planner_name, ', ') into bad
    from unnest(v_ours) o join public.airlines al on al.id = o
    left join public.airline_days x on x.airline_id = o and x.day = d
   where x.source <> 'capture' or x.taken_at <> v_second_at
      or (exists (select 1 from t_pages t where t.airline_id = o and t.kind = 'balance')
          and (x.cash is distinct from 7000000 + o or x.cash_at <= v_first_at));
  assert bad is null, 'the second complete capture didn''t replace the point-in-time figures for: ' || bad;
  -- a backfill or fallback afterwards replaces nothing taken from a complete capture
  perform private.take_snapshot(w, d, now(), 'backfill', false);
  perform private.take_snapshot(w, d, now(), 'fallback', false);
  assert not exists (select 1 from public.airline_days x where x.world_id = w and x.day = d and (x.source <> 'capture' or x.taken_at <> v_second_at)),
    'a backfill or fallback replaced a snapshot taken from a complete capture';

  -- 4. how long a snapshot takes on the copy
  for n in 1 .. 3 loop
    v_t0 := clock_timestamp();
    perform private.take_snapshot(w, d, v_second_at, 'capture');
    v_ms := extract(epoch from clock_timestamp() - v_t0) * 1000;
    v_best := least(coalesce(v_best, v_ms), v_ms);
  end loop;
  raise notice 'a second complete capture of that evening (% pages): one more snapshot at its last page, replacing cash, its time and taken_at; a backfill or fallback after it replaces nothing. A snapshot takes % ms on the copy (best of 3)',
    v_pages, round(v_best);
end
$test$;

do $$ begin raise notice 'the daily snapshot: all checks passed'; end $$;

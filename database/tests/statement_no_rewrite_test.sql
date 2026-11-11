-- The capture stops rewriting bank-statement lines it already has (20261111010000; spec
-- docs/specs/2026-11-11-statement-no-rewrite.md, to-do 204 step 2). Run by database/rehearse.sh on the copy of last
-- night's backup, after the new migrations, inside a transaction that is rolled back. A failed check stops with an error
-- that says which (counts, never figures from the copy).
-- The page used is the copy's latest ok statement page: of each airline's latest statement page, the latest judged ok.
-- Each case stores it again as the capture stores it (private.capture_store(), as capture_ingest() calls it), a minute
-- after the one before.
--   1. Stored again a minute later, it writes no game_statement row (none anywhere is a new row version). How many
--      game_flights and game_payments rows it writes is given as a notice: the measurement the spec asks for.
--   2. A line whose block was set wrong by hand is put right by the same page read again, and only that line is written:
--      (a) the block set wrong only; (b) the block set wrong and its minute folded that way (the line then sits on a
--      flight of its own, as an earlier read that numbered it so would have left it), so the read again must let it go
--      of that flight before the flight is deleted (the foreign key). Either way every row of the page's minutes ends as
--      it was, ids included.
--   3. A flight whose block disappears from the page read again (its block and its lines' block set by hand to a number
--      the page doesn't give) loses its lines' flight_id, as today: no line points at it afterwards, it is gone or has
--      no money, and its block's money and lines are back as they were under the block the page gives.
-- "Written" is measured by row versions: each row's (ctid, xmin) before and after. A row the database writes, even to
-- the same values, gets a new version. capture_store() parses inside a subtransaction (its exception block), so a row it
-- writes carries the subtransaction's id, not pg_current_xact_id(): the spec's "xmin = pg_current_xact_id()::xid"
-- alone would miss it, so both are counted and the versions decide.

create temporary table t_page on commit drop as
  select r.id, r.world_id, r.airline_id, a.game_id, r.page_url, r.rows, r.captured_at
    from (select distinct on (x.airline_id) x.* from public.game_capture_raw x
           where x.kind = 'statement' order by x.airline_id, x.captured_at desc, x.id desc) r
    join public.airlines a on a.id = r.airline_id
   where r.verdict = 'ok'
   order by r.captured_at desc, r.id desc
   limit 1;

-- the page's lines (minute, description, amount) as private.capture_page() reads them
create temporary table t_page_lines on commit drop as
  select distinct case when m.t > p.captured_at + interval '2 days' then m.t - interval '1 year' else m.t end as ts,
         c.c[2] as descr, public.as_num(c.c[3]) as amount
    from t_page p
    cross join lateral jsonb_array_elements(p.rows) e(row_)
    cross join lateral (select array(select x from jsonb_array_elements_text(e.row_) x where x <> '') as c) c
    cross join lateral (select make_timestamptz(extract(year from (p.captured_at at time zone 'UTC'))::int,
                                                substr(c.c[1], 4, 2)::int, substr(c.c[1], 1, 2)::int,
                                                substr(c.c[1], 8, 2)::int, substr(c.c[1], 11, 2)::int, 0, 'UTC') as t) m
   where jsonb_typeof(e.row_) = 'array' and array_length(c.c, 1) >= 3 and c.c[1] ~ '^\d{2}\.\d{2}\. \d{2}:\d{2}'
     and public.as_num(c.c[3]) is not null;
create temporary table t_minutes on commit drop as select distinct ts from t_page_lines;

-- every row version of the three tables, and the ones seen at the last snapshot
create function pg_temp.versions() returns table (tbl text, k text) language sql as $$
  select 'game_statement', ctid::text || '/' || xmin::text from public.game_statement
  union all select 'game_flights', ctid::text || '/' || xmin::text from public.game_flights
  union all select 'game_payments', ctid::text || '/' || xmin::text from public.game_payments
$$;
create temporary table t_snap (tbl text, k text) on commit drop;
create function pg_temp.snap() returns void language sql as $$
  truncate t_snap;
  insert into t_snap select * from pg_temp.versions();
$$;
-- rows written (inserted or rewritten) since the snapshot, and how many more or fewer rows there are
create function pg_temp.written(p_tbl text) returns bigint language sql as $$
  select count(*) from pg_temp.versions() v where v.tbl = p_tbl and not exists (select 1 from t_snap s where s.tbl = v.tbl and s.k = v.k)
$$;
create function pg_temp.added(p_tbl text) returns bigint language sql as $$
  select (select count(*) from pg_temp.versions() v where v.tbl = p_tbl) - (select count(*) from t_snap s where s.tbl = p_tbl)
$$;

-- the page stored again, p_minutes after it first came
create function pg_temp.read_again(p_minutes int) returns jsonb language plpgsql as $$
declare p record; res jsonb;
begin
  select * into p from t_page;
  res := private.capture_store(p.world_id, p.game_id::text, 'statement', p.page_url, p.rows,
                               p.captured_at + make_interval(mins => p_minutes));
  assert coalesce((res ->> 'ok')::boolean, false), 'the page read again didn''t store: ' || coalesce(res ->> 'error', res::text);
  return res;
end
$$;

-- the page's minutes as rows of text: every statement line (with its flight's id when p_ids, else its flight's minute
-- and block), the airline's flights in those minutes (money side; with ids and loads when p_ids) and its payments
create function pg_temp.state(p_ids boolean) returns table (r text) language sql as $$
  select 'S ' || (s.airline, s.ts, s.descr, s.amount, s.side, s.route, s.pax, s.captured_at, s.occ, s.blk, s.world_id, s.airline_id)::text
         || case when p_ids then ' -> ' || coalesce(s.flight_id::text, 'none')
                 else ' -> ' || coalesce((f.posted_at, f.statement_blk)::text, 'none') end
    from public.game_statement s
    join t_page p on p.airline_id = s.airline_id
    left join public.game_flights f on f.id = s.flight_id
   where s.ts in (select ts from t_minutes)
  union all
  select 'F ' || (f.posted_at, f.statement_blk, f.statement_routes, f.maint_registration, f.statement_pax, f.pax_income,
                  f.cargo_income, f.fuel, f.onboard, f.handling, f.landing, f.atc, f.maintenance, f.income_total, f.cost_total,
                  f.money_captured_at)::text
         || case when p_ids then ' ' || (f.id, f.world_id, f.game_date, f.flight_no, f.origin_code, f.dest_code, f.dep_local,
                                         f.arr_local, f.dep_at, f.arr_at, f.route_id, f.aircraft_id, f.registration, f.status,
                                         f.eco_pax, f.bus_pax, f.fst_pax, f.cargo_units, f.loads_captured_at)::text
                 else '' end
    from public.game_flights f
    join t_page p on p.airline_id = f.airline_id
   where f.posted_at in (select ts from t_minutes)
  union all
  select 'P ' || (y.paid_at, y.kind, y.registration, y.aircraft_id, y.descr, y.amount, y.side, y.occ, y.statement_blk)::text
         || case when p_ids then ' ' || y.id::text else '' end
    from public.game_payments y
    join t_page p on p.airline_id = y.airline_id
   where y.paid_at in (select ts from t_minutes)
$$;
create temporary table t_before (r text) on commit drop;
create function pg_temp.differs(p_ids boolean) returns bigint language sql as $$
  select count(*) from ((select r from t_before except all select r from pg_temp.state(p_ids))
                        union all (select r from pg_temp.state(p_ids) except all select r from t_before)) x
$$;

-- ---------------------------------------------------------------- 1. the same page a minute later writes no line
do $test$
declare
  v_top xid8 := pg_current_xact_id(); p record; n_lines bigint; n_new bigint; n_xact bigint; n_gone bigint;
  n_fl bigint; n_fl_gone bigint; n_fl_page bigint; n_pay bigint; n_pay_gone bigint;
begin
  select * into p from t_page;
  assert p.id is not null, 'the copy has no statement page judged ok to read again';
  select count(*) into n_lines from t_page_lines;
  assert n_lines > 0, 'the copy''s latest ok statement page has no lines';
  select count(*) into n_xact from public.game_statement where xmin = v_top::xid;
  assert n_xact = 0, format('%s game_statement rows carried this transaction''s id before the test wrote anything', n_xact);

  perform pg_temp.snap();
  perform pg_temp.read_again(1);
  n_new := pg_temp.written('game_statement'); n_gone := pg_temp.added('game_statement');
  select count(*) into n_xact from public.game_statement where xmin = v_top::xid;
  n_fl := pg_temp.written('game_flights'); n_fl_gone := pg_temp.added('game_flights');
  n_pay := pg_temp.written('game_payments'); n_pay_gone := pg_temp.added('game_payments');
  select count(*) into n_fl_page from public.game_flights f where f.airline_id = p.airline_id and f.posted_at in (select ts from t_minutes);

  assert n_new = 0 and n_gone = 0 and n_xact = 0,
    format('the same page read again a minute later wrote %s game_statement rows (%s with this transaction''s own id), the table %s rows bigger; none expected',
           n_new, n_xact, n_gone);
  raise notice 'case 1: the latest ok statement page (% lines in % minutes) read again a minute later wrote 0 game_statement rows',
    n_lines, (select count(*) from t_minutes);
  raise notice 'case 1, the measurement (spec: game_flights): the same page read again wrote % game_flights rows (the table % rows bigger; the page''s minutes hold % flights of its airline), and % game_payments rows (the table % rows bigger)',
    n_fl, n_fl_gone, n_fl_page, n_pay, n_pay_gone;
end
$test$;

-- ---------------------------------------------------------------- 2. a line whose block was set wrong by hand is put right
do $test$
declare p record; l record; v_wrong int; n bigint; n_other bigint; v_blk int; v_flight bigint; v_spare bigint;
begin
  select * into p from t_page;
  truncate t_before; insert into t_before select * from pg_temp.state(true);
  -- a flight line that isn't its block's first (no income, no maintenance) and names no route, in a block whose other
  -- lines on the page still give it its route, all on the page
  select s.airline, s.ts, s.descr, s.amount, s.occ, s.blk, s.flight_id into l
    from public.game_statement s
    join t_page_lines pl on (pl.ts, pl.descr, pl.amount) = (s.ts, s.descr, s.amount)
   where s.airline_id = p.airline_id and s.flight_id is not null
     and s.descr <> 'Passenger transport income' and s.descr not like 'Maintenance of%'
     and s.descr !~ '\([A-Z]{3}-[A-Z]{3}\)' and private.statement_category(s.descr) <> 'other'
     and exists (select 1 from public.game_statement o join t_page_lines ol on (ol.ts, ol.descr, ol.amount) = (o.ts, o.descr, o.amount)
                  where o.airline_id = s.airline_id and o.ts = s.ts and o.blk = s.blk and o.descr ~ '\([A-Z]{3}-[A-Z]{3}\)')
   order by s.ts desc, s.blk, s.descr, s.amount, s.occ
   limit 1;
  assert l.ts is not null, 'the page has no flight line to set wrong (every one carries a route or starts its block)';
  select coalesce(max(s.blk), 0) + 50 into v_wrong from public.game_statement s where s.airline_id = p.airline_id and s.ts = l.ts;

  -- (a) the block set wrong only
  update public.game_statement set blk = v_wrong
   where (airline, ts, descr, amount, occ) = (l.airline, l.ts, l.descr, l.amount, l.occ);
  perform pg_temp.snap();
  perform pg_temp.read_again(2);
  n := pg_temp.written('game_statement');
  select s.blk, s.flight_id into v_blk, v_flight from public.game_statement s
   where (airline, ts, descr, amount, occ) = (l.airline, l.ts, l.descr, l.amount, l.occ);
  assert v_blk = l.blk and v_flight = l.flight_id,
    format('(a) the line set wrong by hand is in block %s on flight %s after the page read again; block %s on flight %s expected',
           v_blk, v_flight, l.blk, l.flight_id);
  assert n = 1, format('(a) the page read again wrote %s game_statement rows; only the line set wrong (1) expected', n);
  n := pg_temp.differs(true);
  assert n = 0, format('(a) %s rows of the page''s minutes differ from before the line was set wrong', n);

  -- (b) the block set wrong and its minute folded that way: the line sits on a flight of its own
  update public.game_statement set blk = v_wrong
   where (airline, ts, descr, amount, occ) = (l.airline, l.ts, l.descr, l.amount, l.occ);
  perform private.fold_statement(p.airline_id, array[l.ts]);
  select s.flight_id into v_spare from public.game_statement s
   where (airline, ts, descr, amount, occ) = (l.airline, l.ts, l.descr, l.amount, l.occ);
  assert v_spare is not null and v_spare <> l.flight_id,
    format('(b) folded with its block set wrong, the line is on flight %s; a flight of its own expected', coalesce(v_spare::text, 'none'));
  perform pg_temp.snap();
  perform pg_temp.read_again(3);
  select s.blk, s.flight_id into v_blk, v_flight from public.game_statement s
   where (airline, ts, descr, amount, occ) = (l.airline, l.ts, l.descr, l.amount, l.occ);
  assert v_blk = l.blk and v_flight = l.flight_id,
    format('(b) the line is in block %s on flight %s after the page read again; block %s on flight %s expected', v_blk, v_flight,
           l.blk, l.flight_id);
  assert not exists (select 1 from public.game_flights f where f.id = v_spare),
    '(b) the flight the wrong block made is still there after the page read again';
  select count(*) into n_other from pg_temp.versions() v
   where v.tbl = 'game_statement' and not exists (select 1 from t_snap s where s.tbl = v.tbl and s.k = v.k)
     and v.k <> (select s.ctid::text || '/' || s.xmin::text from public.game_statement s
                  where (airline, ts, descr, amount, occ) = (l.airline, l.ts, l.descr, l.amount, l.occ));
  assert n_other = 0, format('(b) the page read again wrote %s game_statement rows besides the line set wrong', n_other);
  n := pg_temp.differs(true);
  assert n = 0, format('(b) %s rows of the page''s minutes differ from before the line was set wrong', n);
  raise notice 'case 2: a line set to a wrong block by hand is put back on its block and flight by the page read again, alone written; folded that way first, its own flight is let go and deleted, and every row of the page''s minutes is as before, ids included';
end
$test$;

-- ---------------------------------------------------------------- 3. a flight whose block disappears loses its lines
do $test$
declare p record; g record; v_wrong int; n bigint; n_lines bigint; v_matched boolean;
begin
  select * into p from t_page;
  truncate t_before; insert into t_before select * from pg_temp.state(false);
  -- a flight of the page's minutes with lines tied, every one on the page; a matched one first (the richer case)
  select f.id, f.posted_at, f.statement_blk, f.flight_no is not null as matched into g
    from public.game_flights f
   where f.airline_id = p.airline_id and f.posted_at in (select ts from t_minutes)
     and exists (select 1 from public.game_statement s where s.flight_id = f.id)
     and not exists (select 1 from public.game_statement s
                      where s.flight_id = f.id
                        and not exists (select 1 from t_page_lines pl where (pl.ts, pl.descr, pl.amount) = (s.ts, s.descr, s.amount)))
   order by (f.flight_no is not null) desc, f.posted_at desc, f.statement_blk
   limit 1;
  assert g.id is not null, 'the page''s minutes have no flight with lines tied';
  select coalesce(max(s.blk), 0) + 50 into v_wrong from public.game_statement s where s.airline_id = p.airline_id and s.ts = g.posted_at;
  select count(*) into n_lines from public.game_statement s where s.flight_id = g.id;
  -- as an earlier read that numbered the block so would have left it: the flight and its lines under that number
  update public.game_flights set statement_blk = v_wrong where id = g.id;
  update public.game_statement set blk = v_wrong where flight_id = g.id;

  perform pg_temp.read_again(4);
  select count(*) into n from public.game_statement s where s.flight_id = g.id;
  assert n = 0, format('%s lines still point at the flight whose block disappeared from the page read again', n);
  assert not exists (select 1 from public.game_flights f where f.id = g.id and f.posted_at is not null),
    'the flight whose block disappeared from the page read again still has money';
  n := pg_temp.differs(false);
  assert n = 0, format('%s rows of the page''s minutes differ from before (by minute and block) once the block is back', n);
  raise notice 'case 3: a % flight whose block disappeared from the page read again let go of its % lines (now %), and its block''s money and lines are back as before under the block the page gives',
    case when g.matched then 'matched' else 'money-only' end, n_lines,
    case when exists (select 1 from public.game_flights f where f.id = g.id) then 'kept without money' else 'deleted' end;
end
$test$;

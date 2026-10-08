drop view if exists public.game_flight_pnl;
drop view if exists public.game_ops_recent;
alter table public.game_statement add column if not exists occ int not null default 1, add column if not exists blk int;
alter table public.game_statement drop constraint if exists game_statement_pkey;
alter table public.game_statement add constraint game_statement_pkey primary key (airline, ts, descr, amount, occ);

create or replace function public.parse_capture(p_id bigint) returns jsonb language plpgsql security definer set search_path = public as $$
declare r record; row_ jsonb; c text[]; n int := 0; cur_date date; yr int := extract(year from now())::int; d text; tsv timestamptz; amt numeric; v_side text; v_descr text; dt date;
  ep int; es int; bp int; bs int; fp int; fs int; cu int; cc int;
  last_ts timestamptz := null; blkn int := 0; maint_pending boolean := false; seen jsonb := '{}'::jsonb; k text; o int; b int;
begin
  select * into r from public.game_capture_raw where id = p_id; if r is null then return '{"ok":false}'; end if;
  if r.kind = 'statement' then
    for row_ in select * from jsonb_array_elements(r.rows) loop
      c := array(select x from jsonb_array_elements_text(row_) x where x <> '');
      if array_length(c,1) < 3 or c[1] !~ '^\d{2}\.\d{2}\. \d{2}:\d{2}' then continue; end if;
      d := substr(c[1],1,6); v_descr := c[2];
      tsv := make_timestamptz(yr, substr(d,4,2)::int, substr(d,1,2)::int, substr(c[1],8,2)::int, substr(c[1],11,2)::int, 0, 'UTC');
      if tsv > now() + interval '2 days' then tsv := tsv - interval '1 year'; end if;
      amt := public.as_num(c[3]); v_side := case when c[3] ~ 'C\s*$' then 'C' else 'D' end;
      if amt is null then continue; end if;
      if last_ts is distinct from tsv then last_ts := tsv; blkn := 0; maint_pending := false; end if;
      if v_descr like 'Maintenance of%' then blkn := blkn + 1; maint_pending := true; b := blkn;
      elsif v_descr = 'Passenger transport income' then if maint_pending then maint_pending := false; else blkn := blkn + 1; end if; b := blkn;
      elsif v_descr ilike 'Leasing rate%' or v_descr ilike 'Week-end closing%' then b := 0;
      else b := greatest(blkn, 1); end if;
      k := tsv::text || '|' || v_descr || '|' || amt::text; o := coalesce((seen->>k)::int, 0) + 1; seen := seen || jsonb_build_object(k, o);
      insert into public.game_statement(airline, ts, descr, amount, side, route, pax, occ, blk)
      values (r.airline, tsv, v_descr, amt, v_side, substring(v_descr from '\(([A-Z]{3}-[A-Z]{3})\)'), (substring(v_descr from 'of (\d+) passengers'))::int, o, b)
      on conflict on constraint game_statement_pkey do update set blk = excluded.blk; n := n + 1;
    end loop;
  elsif r.kind = 'events' then
    for row_ in select * from jsonb_array_elements(r.rows) loop
      c := array(select x from jsonb_array_elements_text(row_) x where x <> '');
      if c[1] ~ '^\w+, \d{2}\.\d{2}\.' then
        d := substring(c[1] from '(\d{2}\.\d{2})\.'); cur_date := make_date(yr, substr(d,4,2)::int, substr(d,1,2)::int);
        if cur_date < current_date - 200 then cur_date := cur_date + interval '1 year'; end if;
        c := c[2:];
      end if;
      if cur_date is null or array_length(c,1) < 2 or c[1] !~ '^\d{2}:\d{2}$' then continue; end if;
      insert into public.game_events(airline, event_date, event_time, descr, credit, debit, balance)
      values (r.airline, cur_date, c[1], c[2], public.as_num(c[3]), public.as_num(c[4]), public.as_num(c[5])) on conflict do nothing; n := n + 1;
    end loop;
  elsif r.kind = 'loads' then
    for row_ in select * from jsonb_array_elements(r.rows) loop
      c := array(select jsonb_array_elements_text(row_));
      if array_length(c,1) < 15 or c[1] !~ '^[A-Z0-9]{2,3}\s?\d{1,5}' or c[4] !~ '\d{2}\.\d{2}\. \d{2}:\d{2}' then continue; end if;
      d := substring(c[4] from '(\d{2}\.\d{2})\.'); dt := make_date(yr, substr(d,4,2)::int, substr(d,1,2)::int); if dt > current_date + 2 then dt := dt - interval '1 year'; end if;
      ep := (substring(c[8] from '^\s*(\d+)'))::int; es := (substring(c[8] from '/\s*(\d+)'))::int;
      bp := (substring(c[10] from '^\s*(\d+)'))::int; bs := (substring(c[10] from '/\s*(\d+)'))::int;
      fp := (substring(c[12] from '^\s*(\d+)'))::int; fs := (substring(c[12] from '/\s*(\d+)'))::int;
      cu := (substring(c[14] from '^\s*(\d+)'))::int; cc := (substring(c[14] from '/\s*(\d+)'))::int;
      insert into public.game_loads(airline, flight_date, code, dep_time, tail, origin, dest, arr_time, status,
        eco, bus, fst, cargo, eco_pax, eco_seats, eco_fare, bus_pax, bus_seats, bus_fare, fst_pax, fst_seats, fst_fare, cargo_units, cargo_cap, cargo_rate)
      values (r.airline, dt, regexp_replace(c[1], '\s+', ' '), substring(c[4] from '(\d{2}:\d{2})'), c[2], c[3], c[5], substring(c[6] from '(\d{2}:\d{2})'), c[15],
        public.as_num(substring(c[8] from '\((\d+)%\)')), public.as_num(substring(c[10] from '\((\d+)%\)')), public.as_num(substring(c[12] from '\((\d+)%\)')), public.as_num(substring(c[14] from '\((\d+)%\)')),
        ep, es, public.as_num(c[7]), bp, bs, public.as_num(c[9]), fp, fs, public.as_num(c[11]), cu, cc, public.as_num(c[13]))
      on conflict (airline, flight_date, code, dep_time) do update set tail = excluded.tail, origin = excluded.origin, dest = excluded.dest, arr_time = excluded.arr_time, status = excluded.status,
        eco = excluded.eco, bus = excluded.bus, fst = excluded.fst, cargo = excluded.cargo, eco_pax = excluded.eco_pax, eco_seats = excluded.eco_seats, eco_fare = excluded.eco_fare,
        bus_pax = excluded.bus_pax, bus_seats = excluded.bus_seats, bus_fare = excluded.bus_fare, fst_pax = excluded.fst_pax, fst_seats = excluded.fst_seats, fst_fare = excluded.fst_fare,
        cargo_units = excluded.cargo_units, cargo_cap = excluded.cargo_cap, cargo_rate = excluded.cargo_rate, captured_at = now();
      n := n + 1;
    end loop;
  elsif r.kind = 'pnl' then
    for row_ in select * from jsonb_array_elements(r.rows) loop
      c := array(select jsonb_array_elements_text(row_));
      if array_length(c,1) < 3 or c[2] !~ 'AS\$' then continue; end if;
      insert into public.game_pnl(airline, captured_on, line, current_p, last_p, total_p) values (r.airline, current_date, c[1], public.as_num(c[2]), public.as_num(c[3]), public.as_num(c[array_length(c,1)]))
      on conflict (airline, captured_on, line) do update set current_p = excluded.current_p, last_p = excluded.last_p, total_p = excluded.total_p; n := n + 1;
    end loop;
  elsif r.kind = 'balance' then
    for row_ in select * from jsonb_array_elements(r.rows) loop
      c := array(select jsonb_array_elements_text(row_));
      if array_length(c,1) >= 3 and c[1] ~ '^\d{3,4}$' then
        insert into public.game_balance(airline, captured_on, account, amount) values (r.airline, current_date, c[1]||' '||c[2], public.as_num(c[3])) on conflict (airline, captured_on, account) do update set amount = excluded.amount; n := n + 1; end if;
      if array_length(c,1) >= 6 and c[4] ~ '^\d{3,4}$' then
        insert into public.game_balance(airline, captured_on, account, amount) values (r.airline, current_date, c[4]||' '||c[5], public.as_num(c[6])) on conflict (airline, captured_on, account) do update set amount = excluded.amount; n := n + 1; end if;
    end loop;
  end if;
  return jsonb_build_object('ok', true, 'kind', r.kind, 'rows', n);
end $$;

delete from public.game_statement where airline in (select distinct airline from public.game_capture_raw where kind = 'statement');
do $$ declare x record; begin
  for x in select id from public.game_capture_raw where kind = 'statement' order by captured_at loop perform public.parse_capture(x.id); end loop;
end $$;

create view public.game_ops_recent with (security_invoker = true) as
with last as (select airline, max(ts) lt from public.game_statement group by 1),
w as (select s.*, l.lt from public.game_statement s join last l using (airline) where s.ts > l.lt - interval '24 hours'
      and s.descr not ilike 'Leasing rate%' and s.descr not ilike 'Week-end closing%' and s.descr not ilike '%deposit%' and s.descr not ilike '%purchase%' and s.descr not ilike '%cabin%' and s.descr not ilike '%configuration%')
select airline, max(lt) last_ts, count(*) filter (where descr = 'Passenger transport income') flights,
  coalesce(sum(amount) filter (where side = 'C'), 0) income, coalesce(sum(amount) filter (where side = 'D'), 0) costs,
  round((extract(epoch from (max(lt) - min(ts))) / 3600)::numeric, 1) hours
from w group by airline;
create view public.game_flight_pnl with (security_invoker = true) as
with lines as (
  select airline, ts, blk, descr, amount, side,
    case when descr = 'Passenger transport income' then 'pax_income' when descr = 'Cargo transport income' then 'cargo_income'
      when descr like 'Fuel%' then 'fuel' when descr like 'On-board services%' then 'onboard'
      when descr like 'Aircraft handling%' or descr like 'Passenger handling%' or descr like 'Cargo logistic%' then 'handling'
      when descr like 'Airport landing fee%' then 'landing' when descr like 'Air traffic control fee%' then 'atc'
      when descr like 'Maintenance of%' then 'maintenance' else 'other' end cat
  from public.game_statement
  where coalesce(blk, 1) > 0 and descr not ilike 'Leasing rate%' and descr not ilike 'Week-end closing%' and descr not ilike '%deposit%'
    and descr not ilike '%purchase%' and descr not ilike '%cabin%' and descr not ilike '%configuration%')
select airline, ts, blk,
  max(substring(descr from '\(([A-Z]{3}-[A-Z]{3})\)')) route,
  count(distinct substring(descr from '\(([A-Z]{3}-[A-Z]{3})\)')) routes_n,
  max((substring(descr from 'Passenger handling of (\d+) passengers'))::int) pax,
  max(substring(descr from 'Maintenance of ([A-Z0-9-]+)')) tail,
  coalesce(sum(amount) filter (where cat = 'pax_income'), 0) pax_income, coalesce(sum(amount) filter (where cat = 'cargo_income'), 0) cargo_income,
  coalesce(sum(amount) filter (where cat = 'fuel'), 0) fuel, coalesce(sum(amount) filter (where cat = 'onboard'), 0) onboard,
  coalesce(sum(amount) filter (where cat = 'handling'), 0) handling, coalesce(sum(amount) filter (where cat = 'landing'), 0) landing,
  coalesce(sum(amount) filter (where cat = 'atc'), 0) atc, coalesce(sum(amount) filter (where cat = 'maintenance'), 0) maintenance,
  coalesce(sum(case when side = 'C' then amount else -amount end), 0) profit
from lines group by airline, ts, blk;
revoke all on public.game_ops_recent, public.game_flight_pnl from anon;
grant select on public.game_ops_recent, public.game_flight_pnl to authenticated;;

alter table public.game_loads
  add column if not exists eco_pax int, add column if not exists eco_seats int, add column if not exists eco_fare numeric,
  add column if not exists bus_pax int, add column if not exists bus_seats int, add column if not exists bus_fare numeric,
  add column if not exists fst_pax int, add column if not exists fst_seats int, add column if not exists fst_fare numeric,
  add column if not exists cargo_units int, add column if not exists cargo_cap int, add column if not exists cargo_rate numeric;

create or replace function public.parse_capture(p_id bigint) returns jsonb language plpgsql security definer set search_path = public as $$
declare r record; row_ jsonb; c text[]; n int := 0; cur_date date; yr int := extract(year from now())::int; d text; tsv timestamptz; amt numeric; side text; descr text; dt date;
  ep int; es int; bp int; bs int; fp int; fs int; cu int; cc int;
begin
  select * into r from public.game_capture_raw where id = p_id; if r is null then return '{"ok":false}'; end if;
  if r.kind = 'statement' then
    for row_ in select * from jsonb_array_elements(r.rows) loop
      c := array(select x from jsonb_array_elements_text(row_) x where x <> '');
      if array_length(c,1) < 3 or c[1] !~ '^\d{2}\.\d{2}\. \d{2}:\d{2}' then continue; end if;
      d := substr(c[1],1,6); descr := c[2];
      tsv := make_timestamptz(yr, substr(d,4,2)::int, substr(d,1,2)::int, substr(c[1],8,2)::int, substr(c[1],11,2)::int, 0, 'UTC');
      if tsv > now() + interval '2 days' then tsv := tsv - interval '1 year'; end if;
      amt := public.as_num(c[3]); side := case when c[3] ~ 'C\s*$' then 'C' else 'D' end;
      if amt is null then continue; end if;
      insert into public.game_statement(airline, ts, descr, amount, side, route, pax)
      values (r.airline, tsv, descr, amt, side, substring(descr from '\(([A-Z]{3}-[A-Z]{3})\)'), (substring(descr from 'of (\d+) passengers'))::int)
      on conflict do nothing; n := n + 1;
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
    -- Load monitoring row: code, tail, origin, "07.10. 04:10 LT", destination, "07.10. 05:23 LT", eco fare, "156 / 156 (100%)", bus fare, bus, first fare, first, cargo rate, "27 / 32 (84%)", status, details
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
select public.parse_capture(25) parsed, public.apply_loads_from_capture('Kingfisher') applied;;

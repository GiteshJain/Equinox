create or replace function public.parse_capture(p_id bigint) returns jsonb language plpgsql security definer set search_path = public as $$
declare r record; row_ jsonb; c text[]; n int := 0; cur_date date; yr int := extract(year from now())::int; d text; tsv timestamptz; amt numeric; side text; descr text; dt date;
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
    for row_ in select * from jsonb_array_elements(r.rows) loop
      c := array(select jsonb_array_elements_text(row_));
      if array_length(c,1) < 8 or c[1] !~ '^[A-Z0-9]{2,3}\s?\d{1,5}' then continue; end if;
      d := substring(c[3] from '(\d{2}\.\d{2})\.'); dt := case when d is null then current_date else make_date(yr, substr(d,4,2)::int, substr(d,1,2)::int) end;
      if dt > current_date + 2 then dt := dt - interval '1 year'; end if;
      insert into public.game_loads(airline, flight_date, code, dep_time, tail, origin, dest, arr_time, eco, bus, fst, cargo, status)
      values (r.airline, dt, regexp_replace(c[1], '\s+', ' '), coalesce(substring(c[3] from '(\d{2}:\d{2})'), ''), c[2], substring(c[3] from '([A-Z]{3})'), substring(c[4] from '([A-Z]{3})'), substring(c[4] from '(\d{2}:\d{2})'),
              public.as_num(split_part(c[5],'%',1)), public.as_num(split_part(c[6],'%',1)), public.as_num(split_part(c[7],'%',1)), public.as_num(split_part(c[8],'%',1)), c[9])
      on conflict (airline, flight_date, code, dep_time) do update set eco = excluded.eco, bus = excluded.bus, fst = excluded.fst, cargo = excluded.cargo, status = excluded.status, captured_at = now(); n := n + 1;
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
delete from public.game_events where airline='Test Airline'; delete from public.game_statement where airline='Test Airline'; delete from public.game_pnl where airline='Test Airline'; delete from public.game_balance where airline='Test Airline'; delete from public.game_loads where airline='Test Airline'; delete from public.game_capture_raw where airline='Test Airline';;

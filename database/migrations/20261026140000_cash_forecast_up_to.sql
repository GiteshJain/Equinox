-- The cash forecast says how much an airline can spend on an order now (26 Oct, Gitesh): the card's Next order shows
-- "up to X" instead of the types it can order ("can order A321neo or A321neo": two variants share a short name). Up to
-- is the largest order, price and cabin together, paid at the latest capture's moment, that keeps settings.order_cushion
-- at every point of the next 14 days, its own weekly lease (lease_estimate_pct of the price) counted as each falls due,
-- as the forecast tests an order (manual §3). It is never below 0. cash_forecast() gives it as up_to, and with
-- next_order (so airline_cards() carries it too).
select set_config('equinox.actor', 'claude', true), set_config('equinox.actor_detail', 'building: next order up to', true);

CREATE OR REPLACE FUNCTION private.fig_cash_forecast(p_airline_id bigint, p_orders jsonb, p_as_of timestamp with time zone, p_lease_map jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare
  w bigint := private.fig_airline_world(p_airline_id);
  v_today date := (p_as_of at time zone 'UTC')::date;
  v_home text; v_amount numeric; v_t0 timestamptz; v_cash0 numeric;
  v_flights bigint; v_income numeric; v_costs numeric; v_per_flight numeric; v_fpd numeric; v_ops_day numeric;
  v_cushion numeric; v_pct numeric; v_lease_map jsonb;
  v_pat timestamptz[]; v_pam numeric[]; v_pwhat text[]; v_prep boolean[];
  v_t timestamptz[]; v_v numeric[]; v_li int; v_cause jsonb;
  v_types jsonb; v_p numeric; v_l numeric;
  v_o jsonb; v_oty record; v_n int; v_sum_p numeric := 0; v_sum_l numeric := 0; v_olist jsonb := '[]'::jsonb; v_orders jsonb;
  v_low_after record; v_next jsonb; v_now jsonb; v_up numeric;
  v_doc jsonb;
begin
  v_home := private.fig_home(p_airline_id);
  v_doc := jsonb_build_object('airline_id', p_airline_id, 'home_airport', v_home, 'as_of', private.fig_ts(p_as_of));
  -- cashForecast(): the airline's latest balance captured in the last 7 days (CAP.bal)
  select b.amount, b.captured_at into v_amount, v_t0
    from public.game_balance b
   where b.airline_id = p_airline_id and b.account like '2800%' and b.captured_on >= v_today - 7 and b.captured_at <= p_as_of
   order by b.captured_at desc limit 1;
  if v_t0 is null or v_home is null then
    return v_doc || jsonb_build_object('status', 'no capture', 'missing', 'a capture: balance sheet, events and bank statement');
  end if;
  v_cash0 := coalesce(v_amount, 0) / 1000000;
  v_doc := v_doc || jsonb_build_object('cash', v_cash0, 'cash_at', private.fig_ts(v_t0));
  -- flight profit from the last 24 hours of the bank statement (game_ops_recent); fewer than 5 flights isn't enough
  select o.flights, o.income, o.costs into v_flights, v_income, v_costs from private.fig_ops_recent(p_airline_id, p_as_of) o;
  if v_flights is null or v_flights < 5 then
    return v_doc || jsonb_build_object('status', 'missing', 'missing', 'a bank statement capture');
  end if;
  v_per_flight := (v_income - v_costs) / v_flights / 1000000;
  -- flightsPerDay(): the planned flights a day
  select coalesce(sum(f.flights_week::numeric / 7), 0) into v_fpd from private.fig_freqs(w, p_airline_id) f where f.live and f.airline_id = p_airline_id;
  v_ops_day := v_per_flight * v_fpd;
  v_cushion := private.fig_num(w, p_airline_id, 'order_cushion') / 1000000;
  v_pct := private.fig_num(w, p_airline_id, 'lease_estimate_pct') / 100;

  -- every scheduled payment after the capture, and each one in its first week again a week later where the game
  -- doesn't list that far yet; up to 14 days after the capture
  with ev as (select e.at, e.amount, e.descr, e.event_date, e.event_time from private.fig_events(w, p_as_of, p_airline_id) e
               where e.airline_id = p_airline_id and e.at > v_t0),
  hz as (select coalesce(max(ev.at), v_t0) as h from ev),
  allp as (select ev.at, ev.amount, ev.descr, false as rep, ev.event_date, ev.event_time from ev
           union all
           select ev.at + interval '168 hours', ev.amount, ev.descr, true, ev.event_date, ev.event_time from ev, hz
            where ev.at <= v_t0 + interval '168 hours' and ev.at + interval '168 hours' > hz.h)
  select coalesce(array_agg(a.at order by a.at, a.rep, a.event_date, a.event_time, a.descr), '{}'),
         coalesce(array_agg(a.amount order by a.at, a.rep, a.event_date, a.event_time, a.descr), '{}'),
         coalesce(array_agg(a.descr order by a.at, a.rep, a.event_date, a.event_time, a.descr), '{}'),
         coalesce(array_agg(a.rep order by a.at, a.rep, a.event_date, a.event_time, a.descr), '{}')
    into v_pat, v_pam, v_pwhat, v_prep
    from allp a where a.at <= v_t0 + interval '336 hours';

  -- the balance at each payment and at the capture's moment on each of the 14 days after it
  select array_agg(y.t order by y.t), array_agg(y.v order by y.t) into v_t, v_v
    from (select x.t, v_cash0 + v_ops_day * (extract(epoch from (x.t - v_t0)) / 86400)
                      - coalesce((select sum(p.a) from unnest(v_pat, v_pam) as p(at, a) where p.at <= x.t), 0) as v
            from (select unnest(v_pat) as t union select v_t0 + i * interval '24 hours' from generate_series(0, 14) i) x) y;
  -- the lowest point (the first, if two are equal), and the payment that makes it: the largest at that moment, else the
  -- largest in the day before it
  select u.i into v_li from unnest(v_v) with ordinality as u(v, i) order by u.v, u.i limit 1;
  select jsonb_build_object('at', private.fig_ts(p.at), 'amount', p.amount, 'what', p.what, 'repeat', p.rep) into v_cause
    from unnest(v_pat, v_pam, v_pwhat, v_prep) with ordinality as p(at, amount, what, rep, i)
   where p.at = v_t[v_li] order by p.amount desc, p.i limit 1;
  if v_cause is null then
    select jsonb_build_object('at', private.fig_ts(p.at), 'amount', p.amount, 'what', p.what, 'repeat', p.rep) into v_cause
      from unnest(v_pat, v_pam, v_pwhat, v_prep) with ordinality as p(at, amount, what, rep, i)
     where p.at <= v_t[v_li] and p.at > v_t[v_li] - interval '24 hours' order by p.amount desc, p.i limit 1;
  end if;

  -- leaseM(): each type's weekly lease, the highest leasing payment seen for it in the events (any airline), else
  -- lease_estimate_pct of its price
  v_lease_map := coalesce(p_lease_map, private.fig_lease_map(w, p_as_of));

  -- each type the airline may buy (airline_aircraft_types): the first day in the next 14 it can be ordered and keep the
  -- cushion (fits() at the capture's moment on each day), with its price (cabin included) and its own lease; how many at
  -- once if today, up to 9 (the most n for which every point from then on keeps the cushion after n orders)
  with ty as (
    select t.id, t.name, t.price / 1000000 as price, cc.code as cabin, coalesce(cc.cost, 0) / 1000000 as cabin_cost,
           (v_lease_map ->> private.fig_type_key(t.name))::numeric as seen_lease
      from public.airline_aircraft_types aat
      join public.aircraft_types t on t.id = aat.aircraft_type_id
      left join public.cabin_configs cc on cc.id = private.fig_order_cabin(p_airline_id, t.id)
     where aat.airline_id = p_airline_id and coalesce(t.price, 0) <> 0),
  tp as (select ty.*, ty.price + ty.cabin_cost as p, coalesce(ty.seen_lease, ty.price * v_pct) as l from ty),
  -- for an order placed on day d, each point from then on and how many of its own lease payments have fallen by then
  -- (worked out once for all types)
  pw as materialized (
    select d.d, x.t, x.v, private.fig_lease_weeks(x.t, v_t0 + d.d * interval '24 hours') as wk
      from generate_series(0, 14) as d(d)
      join unnest(v_t, v_v) as x(t, v) on x.t >= v_t0 + d.d * interval '24 hours'),
  ok as (select tp.id, pw.d, bool_and(pw.v - (tp.p + tp.l * pw.wk) >= v_cushion) as fits
           from tp cross join pw
          group by tp.id, pw.d),
  first_day as (select ok.id, min(ok.d) filter (where ok.fits) as d from ok group by ok.id),
  most as (select tp.id, least(9, floor(min((pw.v - v_cushion) / (tp.p + tp.l * pw.wk))))::int as n
             from tp join pw on pw.d = 0 group by tp.id)
  select coalesce(jsonb_agg(jsonb_build_object(
           'aircraft_type_id', tp.id, 'type', tp.name, 'price', tp.price, 'cabin', tp.cabin, 'cabin_cost', tp.cabin_cost,
           'price_with_cabin', tp.p, 'lease_week', tp.l, 'lease_seen', tp.seen_lease is not null,
           'safe_day', f.d, 'safe_from', private.fig_ts(v_t0 + f.d * interval '24 hours'),
           'count_today', case when f.d = 0 then m.n end) order by tp.id), '[]'::jsonb)
    into v_types
    from tp join first_day f on f.id = tp.id join most m on m.id = tp.id;

  -- orderNow() and fcNext(): what can be ordered today (dearest first), else the first safe day
  select coalesce(jsonb_agg(x ->> 'type' order by (x ->> 'price_with_cabin')::numeric desc, (x ->> 'aircraft_type_id')::bigint), '[]'::jsonb)
    into v_now from jsonb_array_elements(v_types) x where (x ->> 'safe_day')::int = 0;
  if jsonb_array_length(v_now) > 0 then
    v_next := jsonb_build_object('when', 'now', 'types', v_now);
  else
    select jsonb_build_object('when', 'later', 'type', x ->> 'type', 'aircraft_type_id', (x ->> 'aircraft_type_id')::bigint,
                              'safe_day', (x ->> 'safe_day')::int, 'safe_from', x ->> 'safe_from')
      into v_next
      from jsonb_array_elements(v_types) x where x ->> 'safe_day' is not null
     order by (x ->> 'safe_day')::int, (x ->> 'price_with_cabin')::numeric desc, (x ->> 'aircraft_type_id')::bigint limit 1;
    v_next := coalesce(v_next, jsonb_build_object('when', 'not within 14 days'));
  end if;

  -- up to: the largest order (price and cabin, paid at the capture's moment) that keeps the cushion at every point from
  -- then on, its own lease (lease_estimate_pct of the price) counted as it falls (since 26 Oct): the card's Next order
  select greatest(0, min((x.v - v_cushion) / (1 + v_pct * private.fig_lease_weeks(x.t, v_t0)))) into v_up
    from unnest(v_t, v_v) as x(t, v) where x.t >= v_t0;
  v_next := v_next || jsonb_build_object('up_to', round(v_up, 2));

  -- p_orders: several orders tested together, all placed now, each with its own lease (manual §3)
  if p_orders is not null and jsonb_typeof(p_orders) <> 'array' then
    raise exception 'p_orders must be a list: [{"type": "<aircraft type>", "count": 1}, ...]' using errcode = '22023';
  end if;
  if p_orders is not null and jsonb_array_length(p_orders) > 0 then
    for v_o in select * from jsonb_array_elements(p_orders) loop
      if jsonb_typeof(v_o) <> 'object' then raise exception 'p_orders: each order is an object, e.g. {"type": "A321 NEO LIGHT", "count": 1}' using errcode = '22023'; end if;
      select t.id, t.name, coalesce(t.price, 0) / 1000000 as price, cc.code as cabin, coalesce(cc.cost, 0) / 1000000 as cabin_cost,
             (v_lease_map ->> private.fig_type_key(t.name))::numeric as seen_lease,
             exists (select 1 from public.airline_aircraft_types aat where aat.airline_id = p_airline_id and aat.aircraft_type_id = t.id) as may_buy
        into v_oty
        from public.aircraft_types t
        left join public.cabin_configs cc on cc.id = private.fig_order_cabin(p_airline_id, t.id)
       where t.world_id = w and (t.id = (v_o ->> 'aircraft_type_id')::bigint or (v_o ? 'type' and t.name = v_o ->> 'type'))
       order by t.id limit 1;
      if v_oty.id is null then raise exception 'p_orders: no such aircraft type: %', coalesce(v_o ->> 'type', v_o ->> 'aircraft_type_id') using errcode = '22023'; end if;
      v_n := coalesce((v_o ->> 'count')::int, 1);
      if v_n < 1 then raise exception 'p_orders: the count must be 1 or more' using errcode = '22023'; end if;
      v_p := v_oty.price + v_oty.cabin_cost;
      v_l := coalesce(v_oty.seen_lease, v_oty.price * v_pct);
      v_sum_p := v_sum_p + v_n * v_p; v_sum_l := v_sum_l + v_n * v_l;
      v_olist := v_olist || jsonb_build_object('aircraft_type_id', v_oty.id, 'type', v_oty.name, 'count', v_n, 'may_buy', v_oty.may_buy,
                                               'price_with_cabin', v_p, 'lease_week', v_l, 'lease_seen', v_oty.seen_lease is not null);
    end loop;
    select x.t, x.v - (v_sum_p + v_sum_l * private.fig_lease_weeks(x.t, v_t0)) as v
      into v_low_after
      from unnest(v_t, v_v) with ordinality as x(t, v, i)
     order by 2, x.i limit 1;
    v_orders := jsonb_build_object('orders', v_olist,
                                   'safe', private.fig_fits(v_t, v_v, v_t0, 1, v_sum_p, v_sum_l, v_cushion),
                                   'lowest', jsonb_build_object('at', private.fig_ts(v_low_after.t), 'balance', v_low_after.v),
                                   -- the forecast after the orders: each point less their prices and the leases fallen by then
                                   'points', (select jsonb_agg(jsonb_build_object('at', private.fig_ts(x.t),
                                                'balance', x.v - (v_sum_p + v_sum_l * private.fig_lease_weeks(x.t, v_t0))) order by x.i)
                                                from unnest(v_t, v_v) with ordinality as x(t, v, i)));
  end if;

  return v_doc || jsonb_build_object(
    'status', 'ok',
    'profit_per_flight', v_per_flight, 'flights_per_day', v_fpd, 'flight_profit_day', v_ops_day,
    'cushion', v_cushion,
    'up_to', round(v_up, 2),
    'payments', (select coalesce(jsonb_agg(jsonb_build_object('at', private.fig_ts(p.at), 'amount', p.amount, 'what', p.what, 'repeat', p.rep) order by p.i), '[]'::jsonb)
                   from unnest(v_pat, v_pam, v_pwhat, v_prep) with ordinality as p(at, amount, what, rep, i)),
    'payments_next_7_days', (select coalesce(sum(p.a), 0) from unnest(v_pat, v_pam) as p(at, a) where p.at <= v_t0 + interval '168 hours'),
    'points', (select jsonb_agg(jsonb_build_object('at', private.fig_ts(x.t), 'balance', x.v) order by x.i)
                 from unnest(v_t, v_v) with ordinality as x(t, v, i)),
    'lowest', jsonb_build_object('at', private.fig_ts(v_t[v_li]), 'balance', v_v[v_li], 'payment', v_cause),
    'types', v_types,
    'can_order_now', v_now,
    'next_order', v_next)
    || case when v_orders is null then '{}'::jsonb else jsonb_build_object('orders_tested', v_orders) end;
end
$function$;

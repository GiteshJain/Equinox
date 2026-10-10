create or replace view public.capture_cash with (security_invoker = true) as
 WITH bal AS (
         SELECT DISTINCT ON (b.airline_id, b.captured_on) b.world_id,
            b.airline_id,
            b.captured_on,
            b.amount,
            b.captured_at
           FROM game_balance b
          WHERE (b.account ~~ '2800%'::text)
          ORDER BY b.airline_id, b.captured_on, b.captured_at DESC
        )
 SELECT world_id,
    airline_id,
    captured_on AS day,
    amount AS cash,
    ( SELECT sum(e.debit) AS sum
           FROM game_events e
          WHERE ((e.airline_id = bal.airline_id) AND (e.debit > (0)::numeric) AND (e.due_at > bal.captured_at) AND (e.due_at <= (bal.captured_at + '7 days'::interval)))) AS fixed_next7,
    captured_at AS cash_at
   FROM bal
  WHERE (amount IS NOT NULL);

create or replace view public.flight_legs_local with (security_invoker = true) as
 SELECT l.id,
    l.world_id,
    l.airline_id,
    l.rotation_id,
    l.leg_no,
    l.flight_no,
    ((al.iata_code || ' '::text) || l.flight_no) AS flight_code,
    l.origin_code,
    l.dest_code,
    l.aircraft_id,
    l.days_utc,
    l.dep_utc_min,
    l.block_min,
    x.dep_local_min,
    to_char((make_time((x.dep_local_min / 60), (x.dep_local_min % 60), (0)::double precision))::interval, 'HH24:MI'::text) AS dep_local,
    x.days_local,
    x.arr_local_min,
    to_char((make_time((x.arr_local_min / 60), (x.arr_local_min % 60), (0)::double precision))::interval, 'HH24:MI'::text) AS arr_local,
    x.arr_local_day_offset,
    x.arr_utc_min,
    x.arr_utc_day_offset
   FROM (((((((((flight_legs l
     JOIN airlines al ON ((al.id = l.airline_id)))
     LEFT JOIN airports ao ON ((ao.code = l.origin_code)))
     LEFT JOIN world_airports wo ON (((wo.world_id = l.world_id) AND (wo.airport_code = l.origin_code))))
     LEFT JOIN airports ad ON ((ad.code = l.dest_code)))
     LEFT JOIN world_airports wd ON (((wd.world_id = l.world_id) AND (wd.airport_code = l.dest_code))))
     CROSS JOIN LATERAL ( SELECT (round((COALESCE(wo.utc_offset_override, ao.utc_offset) * (60)::numeric)))::integer AS dep_off,
            (round((COALESCE(wd.utc_offset_override, ad.utc_offset) * (60)::numeric)))::integer AS arr_off) o)
     CROSS JOIN LATERAL ( SELECT (l.dep_utc_min + o.dep_off) AS dep_l,
            (l.dep_utc_min + l.block_min) AS arr_u,
            ((l.dep_utc_min + l.block_min) + o.arr_off) AS arr_l) m)
     CROSS JOIN LATERAL ( SELECT (floor(((m.dep_l)::numeric / 1440.0)))::integer AS dep_shift) s)
     CROSS JOIN LATERAL ( SELECT (((m.dep_l % 1440) + 1440) % 1440) AS dep_local_min,
                CASE
                    WHEN (s.dep_shift IS NOT NULL) THEN ( SELECT array_agg(q.wd ORDER BY q.wd) AS array_agg
                       FROM ( SELECT (((((((d.d - 1) + s.dep_shift) % 7) + 7) % 7) + 1))::smallint AS wd
                               FROM unnest(l.days_utc) d(d)) q)
                    ELSE NULL::smallint[]
                END AS days_local,
            (((m.arr_l % 1440) + 1440) % 1440) AS arr_local_min,
            ((floor(((m.arr_l)::numeric / 1440.0)))::integer - s.dep_shift) AS arr_local_day_offset,
            ((m.arr_u)::integer % 1440) AS arr_utc_min,
            (floor(((m.arr_u)::numeric / 1440.0)))::integer AS arr_utc_day_offset) x);

create or replace view public.flight_no_clashes with (security_invoker = true) as
 SELECT f.world_id,
    f.airline_id,
    f.flight_no,
    f.flight_code,
    w.weekday,
    (count(*))::integer AS legs,
    array_agg(f.id ORDER BY f.id) AS leg_ids,
    array_agg(f.aircraft_id ORDER BY f.id) AS aircraft_ids
   FROM (flight_legs_local f
     CROSS JOIN LATERAL unnest(COALESCE(f.days_local, f.days_utc)) w(weekday))
  WHERE (f.flight_no IS NOT NULL)
  GROUP BY f.world_id, f.airline_id, f.flight_no, f.flight_code, w.weekday
 HAVING (count(*) > 1);

create or replace view public.game_flight_pnl with (security_invoker = true) as
 WITH money AS (
         SELECT f.airline_id,
            f.posted_at AS ts,
            (f.statement_blk)::integer AS blk,
            (f.statement_routes)::integer AS routes_n,
                CASE
                    WHEN (f.statement_routes > 0) THEN ((f.origin_code || '-'::text) || f.dest_code)
                    ELSE NULL::text
                END AS route,
            f.statement_pax AS pax,
            f.maint_registration AS tail,
            f.pax_income,
            f.cargo_income,
            f.fuel,
            f.onboard,
            f.handling,
            f.landing,
            f.atc,
            f.maintenance,
            f.income_total AS income,
            f.cost_total AS costs
           FROM game_flights f
          WHERE (f.posted_at IS NOT NULL)
        UNION ALL
         SELECT p.airline_id,
            p.paid_at,
            (p.statement_blk)::integer AS statement_blk,
            0,
            NULL::text,
            NULL::integer,
            NULL::text,
            NULL::numeric,
            NULL::numeric,
            NULL::numeric,
            NULL::numeric,
            NULL::numeric,
            NULL::numeric,
            NULL::numeric,
            NULL::numeric,
                CASE
                    WHEN (p.side = 'C'::text) THEN p.amount
                    ELSE (0)::numeric
                END AS "case",
                CASE
                    WHEN (p.side = 'C'::text) THEN (0)::numeric
                    ELSE p.amount
                END AS amount
           FROM game_payments p
          WHERE ((COALESCE((p.statement_blk)::integer, 1) > 0) AND (p.kind = 'other'::text))
        )
 SELECT al.planner_name AS airline,
    m.ts,
    m.blk,
    max(m.route) AS route,
    (COALESCE(max(m.routes_n), 0))::bigint AS routes_n,
    max(m.pax) AS pax,
    max(m.tail) AS tail,
    trim_scale(COALESCE(sum(m.pax_income), (0)::numeric)) AS pax_income,
    trim_scale(COALESCE(sum(m.cargo_income), (0)::numeric)) AS cargo_income,
    trim_scale(COALESCE(sum(m.fuel), (0)::numeric)) AS fuel,
    trim_scale(COALESCE(sum(m.onboard), (0)::numeric)) AS onboard,
    trim_scale(COALESCE(sum(m.handling), (0)::numeric)) AS handling,
    trim_scale(COALESCE(sum(m.landing), (0)::numeric)) AS landing,
    trim_scale(COALESCE(sum(m.atc), (0)::numeric)) AS atc,
    trim_scale(COALESCE(sum(m.maintenance), (0)::numeric)) AS maintenance,
    trim_scale((sum(m.income) - sum(m.costs))) AS profit
   FROM (money m
     JOIN airlines al ON ((al.id = m.airline_id)))
  GROUP BY m.airline_id, al.planner_name, m.ts, m.blk;

create or replace view public.game_loads with (security_invoker = true) as
 SELECT al.planner_name AS airline,
    f.game_date AS flight_date,
    ((al.iata_code || ' '::text) || f.flight_no) AS code,
    f.dep_local AS dep_time,
    f.registration AS tail,
    f.origin_code AS origin,
    f.dest_code AS dest,
    f.arr_local AS arr_time,
    (f.eco_pct)::numeric AS eco,
    (f.bus_pct)::numeric AS bus,
    (f.fst_pct)::numeric AS fst,
    (f.cargo_pct)::numeric AS cargo,
    f.status,
    f.loads_captured_at AS captured_at,
    f.eco_pax,
    f.eco_seats,
    trim_scale(f.eco_fare) AS eco_fare,
    f.bus_pax,
    f.bus_seats,
    trim_scale(f.bus_fare) AS bus_fare,
    f.fst_pax,
    f.fst_seats,
    trim_scale(f.fst_fare) AS fst_fare,
    f.cargo_units,
    f.cargo_cap,
    trim_scale(f.cargo_rate) AS cargo_rate
   FROM (game_flights f
     JOIN airlines al ON ((al.id = f.airline_id)))
  WHERE (f.flight_no IS NOT NULL);

create or replace view public.game_ops_recent with (security_invoker = true) as
 WITH money AS (
         SELECT f.airline_id,
            f.posted_at AS ts,
            f.income_total AS income,
            f.cost_total AS costs,
            ((f.pax_income IS NOT NULL))::integer AS flights
           FROM game_flights f
          WHERE (f.posted_at IS NOT NULL)
        UNION ALL
         SELECT p.airline_id,
            p.paid_at,
                CASE
                    WHEN (p.side = 'C'::text) THEN p.amount
                    ELSE (0)::numeric
                END AS "case",
                CASE
                    WHEN (p.side = 'C'::text) THEN (0)::numeric
                    ELSE p.amount
                END AS amount,
            0
           FROM game_payments p
          WHERE (p.kind = 'other'::text)
        ), last AS (
         SELECT x.airline_id,
            max(x.ts) AS lt
           FROM ( SELECT f.airline_id,
                    f.posted_at AS ts
                   FROM game_flights f
                  WHERE (f.posted_at IS NOT NULL)
                UNION ALL
                 SELECT p.airline_id,
                    p.paid_at
                   FROM game_payments p) x
          GROUP BY x.airline_id
        ), w AS (
         SELECT m.airline_id,
            m.ts,
            m.income,
            m.costs,
            m.flights,
            l.lt
           FROM (money m
             JOIN last l ON ((l.airline_id = m.airline_id)))
          WHERE (m.ts > (l.lt - '24:00:00'::interval))
        )
 SELECT al.planner_name AS airline,
    max(w.lt) AS last_ts,
    sum(w.flights) AS flights,
    trim_scale(COALESCE(sum(w.income), (0)::numeric)) AS income,
    trim_scale(COALESCE(sum(w.costs), (0)::numeric)) AS costs,
    round((EXTRACT(epoch FROM (max(w.lt) - min(w.ts))) / (3600)::numeric), 1) AS hours
   FROM (w
     JOIN airlines al ON ((al.id = w.airline_id)))
  GROUP BY w.airline_id, al.planner_name;

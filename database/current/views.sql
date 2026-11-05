create or replace view public.backup_runs with (security_invoker = true) as
 SELECT id,
    started_at AS ran_at,
    (details ->> 'kind'::text) AS kind,
    (status = 'ok'::text) AS ok,
    ((details ->> 'tables'::text))::integer AS tables,
    ((details ->> 'rows'::text))::bigint AS rows,
    ((details ->> 'files'::text))::integer AS files,
    ((details ->> 'bytes'::text))::bigint AS bytes,
    (details ->> 'commit_sha'::text) AS commit_sha,
    note,
    (details ->> 'object_key'::text) AS object_key
   FROM job_runs j
  WHERE (job = 'backup'::text);

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

create or replace view public.shared_pairs with (security_invoker = true) as
 WITH ex AS (
         SELECT s.world_id,
            (e.v #>> '{}'::text[])::bigint AS airline_id
           FROM settings s
             CROSS JOIN LATERAL jsonb_array_elements(
                CASE
                    WHEN jsonb_typeof(s.value) = 'array'::text THEN s.value
                    ELSE '[]'::jsonb
                END) e(v)
          WHERE s.key = 'shared_pairs_excluded_airlines'::text AND s.airline_id IS NULL AND jsonb_typeof(e.v) = 'number'::text
        ), bs AS (
         SELECT DISTINCT b.world_id,
            b.airline_id,
            b.airport_code
           FROM airline_bases b
             JOIN airlines a ON a.id = b.airline_id AND a.world_id = b.world_id AND a.active
             JOIN groups g ON g.id = a.group_id AND g.world_id = a.world_id AND g.kind = 'ours'::text
          WHERE (b.role = ANY (ARRAY['hub'::text, 'focus'::text])) AND NOT (EXISTS ( SELECT 1
                   FROM ex
                  WHERE ex.world_id = b.world_id AND ex.airline_id = b.airline_id))
        ), pr AS (
         SELECT x.world_id,
            x.airline_id AS x_al,
            x.airport_code AS x_ap,
            y.airline_id AS y_al,
            y.airport_code AS y_ap
           FROM bs x
             JOIN bs y ON y.world_id = x.world_id AND y.airline_id > x.airline_id AND y.airport_code <> x.airport_code
          WHERE NOT (EXISTS ( SELECT 1
                   FROM bs z
                  WHERE z.world_id = x.world_id AND (z.airline_id = x.airline_id AND z.airport_code = y.airport_code OR z.airline_id = y.airline_id AND z.airport_code = x.airport_code)))
        ), ru(p, q, owner) AS (
         VALUES ('US'::text,'IN'::text,'IN'::text), ('GB'::text,'IN'::text,'IN'::text), ('US'::text,'GB'::text,'US'::text), ('US'::text,'EU'::text,'US'::text), ('US'::text,'CN'::text,'US'::text), ('GB'::text,'EU'::text,'GB'::text), ('GB'::text,'CN'::text,'GB'::text), ('GB'::text,'MY'::text,'GB'::text), ('EU'::text,'CN'::text,'CN'::text), ('IN'::text,'CN'::text,'CN'::text), ('MY'::text,'US'::text,'MY'::text), ('MY'::text,'IN'::text,'MY'::text), ('MY'::text,'CN'::text,'MY'::text), ('MY'::text,'EU'::text,'MY'::text)
        ), po AS (
         SELECT pr.world_id,
            pr.x_al,
            pr.x_ap,
            pr.y_al,
            pr.y_ap,
                CASE ru.owner
                    WHEN kx.k THEN pr.x_al
                    WHEN ky.k THEN pr.y_al
                    ELSE NULL::bigint
                END AS rule_owner
           FROM pr
             LEFT JOIN airports ax ON ax.code = pr.x_ap
             LEFT JOIN countries cx ON cx.code = ax.country_code
             LEFT JOIN airports ay ON ay.code = pr.y_ap
             LEFT JOIN countries cy ON cy.code = ay.country_code
             CROSS JOIN LATERAL ( SELECT
                        CASE
                            WHEN ax.country_code = ANY (ARRAY['US'::text, 'GB'::text, 'IN'::text, 'CN'::text, 'MY'::text]) THEN ax.country_code
                            WHEN cx.region = 'Europe'::text THEN 'EU'::text
                            ELSE NULL::text
                        END AS k) kx
             CROSS JOIN LATERAL ( SELECT
                        CASE
                            WHEN ay.country_code = ANY (ARRAY['US'::text, 'GB'::text, 'IN'::text, 'CN'::text, 'MY'::text]) THEN ay.country_code
                            WHEN cy.region = 'Europe'::text THEN 'EU'::text
                            ELSE NULL::text
                        END AS k) ky
             LEFT JOIN ru ON ru.p = kx.k AND ru.q = ky.k OR ru.p = ky.k AND ru.q = kx.k
        ), orr AS (
         SELECT po.world_id,
            po.x_al,
            po.x_ap,
            po.y_al,
            po.y_ap,
            po.rule_owner,
            ( SELECT r.id
                   FROM routes r
                  WHERE r.world_id = po.world_id AND NOT r.removed AND r.shares_route_id IS NULL AND (r.airline_id = po.x_al AND r.hub_code = po.x_ap AND r.dest_code = po.y_ap OR r.airline_id = po.y_al AND r.hub_code = po.y_ap AND r.dest_code = po.x_ap)
                  ORDER BY (NOT r.airline_id IS DISTINCT FROM po.rule_owner) DESC, r.id
                 LIMIT 1) AS owner_route_id
           FROM po
        ), pa AS (
         SELECT o.world_id,
            o.x_al,
            o.x_ap,
            o.y_al,
            o.y_ap,
            o.rule_owner,
            o.owner_route_id,
            COALESCE(ro.airline_id, o.rule_owner) AS owner_al,
            ro.id AS ro_id,
            ro.airline_id AS ro_al,
            j.id AS j_id,
            j.airline_id AS j_al,
            j.created_at AS j_created
           FROM orr o
             LEFT JOIN routes ro ON ro.id = o.owner_route_id
             LEFT JOIN routes j ON j.shares_route_id = ro.id AND j.world_id = ro.world_id AND NOT j.removed
        )
 SELECT world_id,
    owner_al AS owner_airline_id,
        CASE owner_al
            WHEN x_al THEN y_al
            WHEN y_al THEN x_al
            ELSE NULL::bigint
        END AS joiner_airline_id,
    ro_id AS owner_route_id,
    j_id AS joiner_route_id,
        CASE owner_al
            WHEN x_al THEN x_ap
            WHEN y_al THEN y_ap
            ELSE NULL::text
        END AS owner_base,
        CASE owner_al
            WHEN x_al THEN y_ap
            WHEN y_al THEN x_ap
            ELSE NULL::text
        END AS joiner_base,
    COALESCE(( SELECT sum(COALESCE(cardinality(l.days_utc), 7)) AS sum
           FROM rotations rt
             JOIN flight_legs l ON l.rotation_id = rt.id
          WHERE rt.route_id = pa.ro_id AND rt.airline_id = pa.ro_al), 0::bigint)::integer AS owner_flights_week,
    COALESCE(( SELECT sum(COALESCE(cardinality(l.days_utc), 7)) AS sum
           FROM rotations rt
             JOIN flight_legs l ON l.rotation_id = rt.id
          WHERE rt.route_id = pa.j_id AND rt.airline_id = pa.j_al), 0::bigint)::integer AS joiner_flights_week,
    (j_created AT TIME ZONE 'UTC'::text)::date AS joined_on
   FROM pa;

-- Keep every payment out of the flight-money views (bug found by the Review chat, 10 Oct 2026).
--
-- game_flight_pnl and game_ops_recent add back the statement lines that aren't tied to a flight, as the old views did,
-- but they recognised leases, salaries, deposits, purchases, cabins and refits by their wording. The game now calls the
-- weekly salary payment "Payment of employee salaries" (it used to be "Week-end closing ..."), so it slipped through and
-- counted as a flight with no route: 4 rows from 8 Oct (Ryanair -1.26M, Pan Am -0.80M, Virgin -0.71M, Kingfisher
-- -0.71M), making a day's flight profit low on salary day, in the planner, export_capture() and the weekly report.
--
-- Both views now add back only payments of kind 'other' (game_payments.kind, set by private.payment_kind(), which knows
-- both salary labels). Same columns, same rows otherwise. Nothing is removed or revoked: create or replace keeps the
-- views' grants; their descriptions are updated below.

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

comment on view public.game_flight_pnl is 'Each statement block''s income and costs by type and its profit, as before #13, from game_flights only: payments that aren''t flights (salaries, leases and the like) are left out. Read by the planner (Review: route profit, aircraft) and export_capture(). Shows the caller only what it may read.';
comment on view public.game_ops_recent is 'Each airline''s last 24 hours before its latest statement line, as before #13: flights, income, costs and hours, from game_flights and the statement lines the capture couldn''t name (game_payments of kind other); salaries, leases, purchases, deposits, cabins and refits are left out. Read by the planner (Review: the group today; the cash forecast''s flight profit) and export_capture(). Shows the caller only what it may read.';

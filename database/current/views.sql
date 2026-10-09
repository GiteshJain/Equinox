create or replace view public.game_flight_pnl as
 WITH lines AS (
         SELECT game_statement.airline,
            game_statement.ts,
            game_statement.blk,
            game_statement.descr,
            game_statement.amount,
            game_statement.side,
                CASE
                    WHEN (game_statement.descr = 'Passenger transport income'::text) THEN 'pax_income'::text
                    WHEN (game_statement.descr = 'Cargo transport income'::text) THEN 'cargo_income'::text
                    WHEN (game_statement.descr ~~ 'Fuel%'::text) THEN 'fuel'::text
                    WHEN (game_statement.descr ~~ 'On-board services%'::text) THEN 'onboard'::text
                    WHEN ((game_statement.descr ~~ 'Aircraft handling%'::text) OR (game_statement.descr ~~ 'Passenger handling%'::text) OR (game_statement.descr ~~ 'Cargo logistic%'::text)) THEN 'handling'::text
                    WHEN (game_statement.descr ~~ 'Airport landing fee%'::text) THEN 'landing'::text
                    WHEN (game_statement.descr ~~ 'Air traffic control fee%'::text) THEN 'atc'::text
                    WHEN (game_statement.descr ~~ 'Maintenance of%'::text) THEN 'maintenance'::text
                    ELSE 'other'::text
                END AS cat
           FROM game_statement
          WHERE ((COALESCE(game_statement.blk, 1) > 0) AND (game_statement.descr !~~* 'Leasing rate%'::text) AND (game_statement.descr !~~* 'Week-end closing%'::text) AND (game_statement.descr !~~* '%deposit%'::text) AND (game_statement.descr !~~* '%purchase%'::text) AND (game_statement.descr !~~* '%cabin%'::text) AND (game_statement.descr !~~* '%configuration%'::text))
        )
 SELECT airline,
    ts,
    blk,
    max("substring"(descr, '\(([A-Z]{3}-[A-Z]{3})\)'::text)) AS route,
    count(DISTINCT "substring"(descr, '\(([A-Z]{3}-[A-Z]{3})\)'::text)) AS routes_n,
    max(("substring"(descr, 'Passenger handling of (\d+) passengers'::text))::integer) AS pax,
    max("substring"(descr, 'Maintenance of ([A-Z0-9-]+)'::text)) AS tail,
    COALESCE(sum(amount) FILTER (WHERE (cat = 'pax_income'::text)), (0)::numeric) AS pax_income,
    COALESCE(sum(amount) FILTER (WHERE (cat = 'cargo_income'::text)), (0)::numeric) AS cargo_income,
    COALESCE(sum(amount) FILTER (WHERE (cat = 'fuel'::text)), (0)::numeric) AS fuel,
    COALESCE(sum(amount) FILTER (WHERE (cat = 'onboard'::text)), (0)::numeric) AS onboard,
    COALESCE(sum(amount) FILTER (WHERE (cat = 'handling'::text)), (0)::numeric) AS handling,
    COALESCE(sum(amount) FILTER (WHERE (cat = 'landing'::text)), (0)::numeric) AS landing,
    COALESCE(sum(amount) FILTER (WHERE (cat = 'atc'::text)), (0)::numeric) AS atc,
    COALESCE(sum(amount) FILTER (WHERE (cat = 'maintenance'::text)), (0)::numeric) AS maintenance,
    COALESCE(sum(
        CASE
            WHEN (side = 'C'::text) THEN amount
            ELSE (- amount)
        END), (0)::numeric) AS profit
   FROM lines
  GROUP BY airline, ts, blk;

create or replace view public.game_ops_recent as
 WITH last AS (
         SELECT game_statement.airline,
            max(game_statement.ts) AS lt
           FROM game_statement
          GROUP BY game_statement.airline
        ), w AS (
         SELECT s.airline,
            s.ts,
            s.descr,
            s.amount,
            s.side,
            s.route,
            s.pax,
            s.captured_at,
            s.occ,
            s.blk,
            l.lt
           FROM (game_statement s
             JOIN last l USING (airline))
          WHERE ((s.ts > (l.lt - '24:00:00'::interval)) AND (s.descr !~~* 'Leasing rate%'::text) AND (s.descr !~~* 'Week-end closing%'::text) AND (s.descr !~~* '%deposit%'::text) AND (s.descr !~~* '%purchase%'::text) AND (s.descr !~~* '%cabin%'::text) AND (s.descr !~~* '%configuration%'::text))
        )
 SELECT airline,
    max(lt) AS last_ts,
    count(*) FILTER (WHERE (descr = 'Passenger transport income'::text)) AS flights,
    COALESCE(sum(amount) FILTER (WHERE (side = 'C'::text)), (0)::numeric) AS income,
    COALESCE(sum(amount) FILTER (WHERE (side = 'D'::text)), (0)::numeric) AS costs,
    round((EXTRACT(epoch FROM (max(lt) - min(ts))) / (3600)::numeric), 1) AS hours
   FROM w
  GROUP BY airline;

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
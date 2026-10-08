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
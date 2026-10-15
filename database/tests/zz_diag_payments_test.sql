-- TEMPORARY diagnostic for the briefing pull request (removed before review): which game_flight_pnl rows
-- flight_views_payments_test.sql counts as payments on this copy. Counts and kinds only.
do $diag$
declare s text;
begin
  select string_agg(format('%s/%s/blk%s/%s/flightrow:%s=%s', x.kind, x.has_route, x.blk, x.day, x.is_flight_row, x.n), '; ' order by x.day, x.kind) into s
    from (select p.kind, (f.route is not null) as has_route, f.blk, (f.ts at time zone 'UTC')::date as day,
                 exists (select 1 from public.game_flights g where g.airline_id = a.id and g.posted_at = f.ts and g.statement_blk::int = f.blk) as is_flight_row,
                 count(*) as n
            from public.game_flight_pnl f
            join public.airlines a on a.planner_name = f.airline
            join public.game_payments p on p.airline_id = a.id and p.paid_at = f.ts and coalesce(p.statement_blk::integer, 1) = f.blk
           where p.kind <> 'other'
           group by 1, 2, 3, 4, 5) x;
  raise notice 'diag: %', coalesce(s, 'none');
end
$diag$;

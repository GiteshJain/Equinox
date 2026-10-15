-- TEMPORARY diagnostic for the briefing pull request (removed before review): the unnamed ('other') statement lines that
-- share their minute and block with a named payment on this copy, by label with digits and registrations masked.
do $diag$
declare s text;
begin
  select string_agg(format('%s beside %s: %s', x.label, x.kinds, x.n), '; ' order by x.n desc) into s
    from (select regexp_replace(regexp_replace(o.descr, '[A-Z0-9]{1,3}-[A-Z0-9]{2,6}', '<reg>', 'g'), '[0-9]+', '#', 'g') as label,
                 string_agg(distinct p.kind, '+') as kinds, count(*) as n
            from public.game_payments o
            join public.game_payments p on p.airline_id = o.airline_id and p.paid_at = o.paid_at
                                       and coalesce(p.statement_blk::integer, 1) = coalesce(o.statement_blk::integer, 1) and p.kind <> 'other'
           where o.kind = 'other'
           group by 1) x;
  raise notice 'diag: %', coalesce(s, 'none');
end
$diag$;

-- Profit leaves out what's put back into the fleet, from the bank statement (26 Oct, Gitesh: "reinvestment should be
-- left out"). Profit a day is the change in cash between two reported days plus that interval's order payments
-- (fig_capex), which came from the spending log typed by hand. From 23 Oct nothing more was logged while 1.6 to 4.1M of
-- deposits and cabins left each airline almost every day, and a logged day often differed from the day the game took
-- the money, so the cards and sparklines swung into the red (Pan Am 0.38M a day over 7 days, 1.29M without them). Now
-- the interval's payments come from the statement, between the two days' balance captures: security deposits (a
-- refund, as for Kingfisher's A350s, counts against them), cabin installations and pilot training, and auction bid
-- provisions (their refunds count against them). Before the statement's payments begin (7 Oct), or for a day typed by
-- hand, the spending log as before. Cash itself is unchanged.
select set_config('equinox.actor', 'claude', true), set_config('equinox.actor_detail', 'building: profit without reinvestment', true);

CREATE OR REPLACE FUNCTION private.fig_capex(p_airline_id bigint, p_d0 date, p_d1 date)
 RETURNS numeric
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  -- the money put back into the fleet between two reported days (since 26 Oct): from the bank statement, between the
  -- two days' balance captures, every security deposit (one refunded counts against it), aircraft purchase, cabin
  -- installation, refit and pilot training, and an auction's bid provision (its refund counts against it); before the statement's payments begin, or
  -- for a day typed by hand, the spending log as before
  with t as (select (select max(b.captured_at) from public.game_balance b
                      where b.airline_id = p_airline_id and b.account like '2800%' and b.captured_on = p_d0) as t0,
                    (select max(b.captured_at) from public.game_balance b
                      where b.airline_id = p_airline_id and b.account like '2800%' and b.captured_on = p_d1) as t1,
                    (select min(p.paid_at) from public.game_payments p where p.airline_id = p_airline_id) as since)
  select case when t.t0 is not null and t.t1 is not null and t.since is not null and t.t0 >= t.since then
           coalesce((select sum(case when p.side = 'C' then -p.amount else p.amount end) from public.game_payments p
                      where p.airline_id = p_airline_id and p.paid_at > t.t0 and p.paid_at <= t.t1
                        and (p.kind in ('deposit', 'cabin', 'purchase', 'refit') or (p.kind = 'other' and p.descr ilike '%provisions for bid%'))), 0) / 1000000
         else (select coalesce(sum(s.amount), 0) / 1000000 from public.spending_log s
                where s.airline_id = p_airline_id and s.kind <> 'loss' and s.spent_on > p_d0 and s.spent_on <= p_d1) end
    from t
$function$;

comment on function private.fig_capex(bigint, date, date) is 'The captured figures: the money put back into the fleet between two reported days (millions), which profit a day adds back to the change in cash. From the bank statement between the two days'' balance captures (deposits, cabins and pilot training, bid provisions; refunds count against them), else the spending log (since 26 Oct).';

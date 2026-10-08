-- each airline's flight income and flight costs over the 24 hours before its latest statement line (leases, week-end closing, deposits and cabin charges left out)
create or replace view public.game_ops_recent with (security_invoker = true) as
with last as (select airline, max(ts) lt from public.game_statement group by 1),
w as (select s.*, l.lt from public.game_statement s join last l using (airline) where s.ts > l.lt - interval '24 hours'
      and s.descr not ilike 'Leasing rate%' and s.descr not ilike 'Week-end closing%' and s.descr not ilike '%deposit%' and s.descr not ilike '%purchase%' and s.descr not ilike '%cabin%' and s.descr not ilike '%configuration%')
select airline, max(lt) last_ts,
  count(*) filter (where descr = 'Passenger transport income') flights,
  coalesce(sum(amount) filter (where side = 'C'), 0) income,
  coalesce(sum(amount) filter (where side = 'D'), 0) costs,
  round((extract(epoch from (max(lt) - min(ts))) / 3600)::numeric, 1) hours
from w group by airline;
revoke all on public.game_ops_recent from anon;
grant select on public.game_ops_recent to authenticated;
select airline, flights, income, costs, hours from public.game_ops_recent;;

-- one row per flight from the bank statement: every line of a flight carries the same arrival minute
create or replace view public.game_flight_pnl with (security_invoker = true) as
with lines as (
  select airline, ts, descr, amount, side,
    case
      when descr = 'Passenger transport income' then 'pax_income'
      when descr = 'Cargo transport income' then 'cargo_income'
      when descr like 'Fuel%' then 'fuel'
      when descr like 'On-board services%' then 'onboard'
      when descr like 'Aircraft handling%' or descr like 'Passenger handling%' or descr like 'Cargo logistic%' then 'handling'
      when descr like 'Airport landing fee%' then 'landing'
      when descr like 'Air traffic control fee%' then 'atc'
      when descr like 'Maintenance of%' then 'maintenance'
      else 'other' end cat
  from public.game_statement
  where descr not ilike 'Leasing rate%' and descr not ilike 'Week-end closing%' and descr not ilike '%deposit%'
    and descr not ilike '%purchase%' and descr not ilike '%cabin%' and descr not ilike '%configuration%')
select airline, ts,
  max(substring(descr from '\(([A-Z]{3}-[A-Z]{3})\)')) route,
  count(distinct substring(descr from '\(([A-Z]{3}-[A-Z]{3})\)')) routes_n,
  max((substring(descr from 'Passenger handling of (\d+) passengers'))::int) pax,
  max(substring(descr from 'Maintenance of ([A-Z0-9-]+)')) tail,
  coalesce(sum(amount) filter (where cat = 'pax_income'), 0) pax_income,
  coalesce(sum(amount) filter (where cat = 'cargo_income'), 0) cargo_income,
  coalesce(sum(amount) filter (where cat = 'fuel'), 0) fuel,
  coalesce(sum(amount) filter (where cat = 'onboard'), 0) onboard,
  coalesce(sum(amount) filter (where cat = 'handling'), 0) handling,
  coalesce(sum(amount) filter (where cat = 'landing'), 0) landing,
  coalesce(sum(amount) filter (where cat = 'atc'), 0) atc,
  coalesce(sum(amount) filter (where cat = 'maintenance'), 0) maintenance,
  coalesce(sum(case when side = 'C' then amount else -amount end), 0) profit
from lines group by airline, ts;
revoke all on public.game_flight_pnl from anon;
grant select on public.game_flight_pnl to authenticated;;

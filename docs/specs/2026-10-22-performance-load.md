# Performance load: figures that time out when many are read at once (22 Oct 2026)

## What happened
On 21 Oct, after the evening capture, Performance showed "Couldn't read the profit by day" and then "Couldn't read the
fare ladder": "canceling statement due to statement timeout". Each figure takes about 0.5 seconds on its own, but the
screen asks for about twenty at once (six airlines' profit, cash forecast and fare ladder, the cards, growth signals, hub
progress). On the small database they slow one another: the database's own record of the planner's calls showed
airline_profit averaging 1.2 s with a peak of 7.5 s, cash_forecast 7.9 s and fare_ladder 6.4 s, against staff's 8 s limit.

## The change
1. **Database:** the twelve figure functions the planner reads get their own 30 second statement limit
   (`alter function ... set statement_timeout = '30s'`), the same as export_for_report (17 Oct). The data API applies a
   function's own limit, so nothing else changes. Migration `20261022050000_figures_timeout_staff.sql`.
2. **Planner:** Performance's figure reads go through a queue, `data/limit.ts`, at most four at a time, in the order asked.
   The other screens are not changed.

## Read differently from what Gitesh was told in chat
He was told the fare ladder would also load only when an airline is opened. This build does not: the ladders still load
for every airline, but in turn behind the queue, so the screen needs no new states. Say if that should change.

## Checks
- `data/limit.test.ts`: never more than the limit at once, in order, a failure frees its place.
- `database/tests/figures_timeout_test.sql`: the twelve carry the 30 s limit and keep their empty search_path; no other
  function in public has a limit but export_for_report and capture_fare_actions.

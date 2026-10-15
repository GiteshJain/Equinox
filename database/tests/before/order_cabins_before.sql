-- Saved by database/rehearse.sh before the pending changes run, into the schema rehearsal_before, and compared
-- afterwards by database/tests/order_cabins_test.sql (spec docs/specs/2026-10-15-last-leftovers.md §1): the cabin layout
-- an order of each type comes with for each airline (private.fig_order_cabin()), for every airline and every type of its
-- world. Before 20261015220000_last_leftovers.sql the function worked it out from the cabin names; since, it reads the data.
create table rehearsal_before.order_cabins as
select a.id as airline_id, t.id as aircraft_type_id, private.fig_order_cabin(a.id, t.id) as config_id
  from public.airlines a
  join public.aircraft_types t on t.world_id = a.world_id;

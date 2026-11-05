-- Saved by database/rehearse.sh before the pending changes run, into the schema rehearsal_before, and counted afterwards
-- by database/tests/fare_ladder_test.sql §11 (spec docs/specs/2026-10-21-frequencies-and-fares.md §3: "show the counts of
-- mismatches before and after on the rehearsal's copy"): each of our airlines' routes and cabins with the fare index as
-- private.fig_fare_ladder() read it before the change (the latest captured fare against the first, times the launch
-- level). Left empty when the copy has no fare ladder yet. Since 26 Oct (spec
-- docs/specs/2026-10-26-fare-ladder-per-direction.md §4) also each row's direction (none before the ladder went per
-- direction), so frequencies_and_fares_test.sql §4 can check each direction starts at the level it had. Since 4 Nov (spec
-- docs/specs/2026-11-04-fare-default-from-market.md: "the change must not make it noticeably slower") each airline's
-- call is timed as it is made (rehearsal_before.fare_ladder_ms, the same calls, one at a time), and
-- fare_default_from_market_test.sql times them again after the changes.
create table rehearsal_before.fare_index (airline_id bigint, iata text, route_id bigint, hub text, dest text, cabin text,
                                          fare_index numeric, index_matches boolean, level numeric, direction text);
create table rehearsal_before.fare_ladder_ms (airline_id bigint, iata text, ms integer, rows integer);

do $save$
declare x record; t0 timestamptz; d jsonb;
begin
  if to_regprocedure('private.fig_fare_ladder(bigint, timestamp with time zone)') is not null then
    for x in select f.airline_id, a.iata_code from private.fig_airlines(private.fig_world(null)) f
               join public.airlines a on a.id = f.airline_id order by a.position nulls last, a.id loop
      t0 := clock_timestamp();
      d := private.fig_fare_ladder(x.airline_id, now());
      insert into rehearsal_before.fare_ladder_ms (airline_id, iata, ms, rows)
      values (x.airline_id, x.iata_code, round(extract(epoch from clock_timestamp() - t0) * 1000), jsonb_array_length(d -> 'routes'));
      insert into rehearsal_before.fare_index (airline_id, iata, route_id, hub, dest, cabin, fare_index, index_matches, level, direction)
      select x.airline_id, x.iata_code, (e ->> 'route_id')::bigint, e ->> 'hub', e ->> 'dest', e ->> 'cabin', (e ->> 'fare_index')::numeric,
             (e ->> 'index_matches')::boolean, (e ->> 'level')::numeric, e ->> 'direction'
        from jsonb_array_elements(d -> 'routes') e;
    end loop;
  end if;
end
$save$;

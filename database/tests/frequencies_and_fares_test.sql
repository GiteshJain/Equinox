-- New frequencies and the fare ladder, on the copy (migration 20261021230000_frequencies_and_fares.sql; spec
-- docs/specs/2026-10-21-frequencies-and-fares.md §3: "show the counts of mismatches before and after on the rehearsal's
-- copy"). Run by database/rehearse.sh on the copy of last night's backup, after the new migrations, inside a transaction
-- that is rolled back; the hand-made cases are in fare_ladder_test.sql. Counts and route ids only, never rows.
--   1. Our routes and cabins off their level by the old index (the latest captured fare against the first, times the
--      launch level: database/tests/before/frequencies_and_fares_before.sql saved it before the changes) and by the new
--      one (each flight of the latest captured day against its direction's fare on 21 Oct 2026, when every route was at
--      its launch level), and how many get a set-back change (the route ids of those off, to look at).
--   2. Ryanair's four early cuts (BRI–CDG, CDG–SOF, CDG–SPU, CDG–VLC): off before, none off after.
--   3. How many directions had flights more than 1% apart on their baseline day (where every route at its launch level
--      would have them all the same): a new flight the game priced at the default price shows here.
create temporary table t_fl_new (airline_id bigint, iata text, route_id bigint, hub text, dest text, cabin text, fare_index numeric,
                                 index_matches boolean, fix boolean) on commit drop;
do $test$
declare w bigint := private.fig_world(null); n_new int := 0; n_off int := 0; n_fix int := 0; n_old int; n_old_all int; ids text;
  cuts_found int := 0; cuts_old_off int; cuts_new_off int := 0; n_mixed int; al record; d jsonb;
begin
  for al in select x.airline_id, a.iata_code from private.fig_airlines(w) x join public.airlines a on a.id = x.airline_id order by x.ord loop
    d := private.fig_fare_ladder(al.airline_id, now());
    insert into t_fl_new
    select al.airline_id, al.iata_code, (e ->> 'route_id')::bigint, e ->> 'hub', e ->> 'dest', e ->> 'cabin', (e ->> 'fare_index')::numeric,
           (e ->> 'index_matches')::boolean, (e ->> 'fix')::boolean
      from jsonb_array_elements(d -> 'routes') e;
  end loop;
  select count(*), count(*) filter (where index_matches = false), count(*) filter (where fix) into n_new, n_off, n_fix from t_fl_new;
  -- Ryanair's four early cuts (spec part 3): BRI–CDG, CDG–SOF, CDG–SPU, CDG–VLC, either way round
  select count(*), count(*) filter (where n.index_matches = false) into cuts_found, cuts_new_off
    from t_fl_new n
   where n.iata = 'FR' and n.cabin = 'economy'
     and least(n.hub, n.dest) || '–' || greatest(n.hub, n.dest) in ('BRI–CDG', 'CDG–SOF', 'CDG–SPU', 'CDG–VLC');
  if to_regclass('rehearsal_before.fare_index') is not null then
    select count(*), count(*) filter (where b.index_matches = false) into n_old_all, n_old from rehearsal_before.fare_index b;
    select count(*) filter (where b.index_matches = false) into cuts_old_off
      from rehearsal_before.fare_index b
     where b.iata = 'FR' and b.cabin = 'economy'
       and least(b.hub, b.dest) || '–' || greatest(b.hub, b.dest) in ('BRI–CDG', 'CDG–SOF', 'CDG–SPU', 'CDG–VLC');
  end if;
  -- the directions whose flights on their baseline day (the latest captured day on or before 21 Oct 2026) sold at fares
  -- more than 1% apart, where every route at its launch level would have them all the same
  with f as (select distinct on (g.game_date, g.flight_no, g.airline_id) g.airline_id, g.origin_code, g.dest_code, g.game_date, g.eco_fare
               from public.game_flights g join private.fig_airlines(w) x on x.airline_id = g.airline_id
              where g.flight_no is not null and g.eco_fare > 0 and g.game_date <= date '2026-10-21'
              order by g.game_date, g.flight_no, g.airline_id, g.id desc),
       lastday as (select f.airline_id, f.origin_code, f.dest_code, max(f.game_date) as day from f group by 1, 2, 3)
  select count(*) into n_mixed
    from (select f.airline_id, f.origin_code, f.dest_code from f join lastday l using (airline_id, origin_code, dest_code)
           where f.game_date = l.day group by 1, 2, 3 having max(f.eco_fare) > min(f.eco_fare) * 1.01) m;
  select string_agg(distinct n.route_id::text, ', ') into ids from t_fl_new n where n.index_matches = false;
  assert cuts_new_off = 0, format('of Ryanair''s %s early cuts found, %s are still off their level by the new index', cuts_found, cuts_new_off);
  raise notice 'on the copy: % routes and cabins; off their level by the old index (the latest fare against the first): % of %; by the new (each flight against its 21 Oct fare): % of %, % of them set back%',
    n_new, coalesce(n_old::text, 'not saved'), coalesce(n_old_all::text, '—'), n_off, n_new, n_fix, case when ids is null then '' else ' (route ids ' || ids || ')' end;
  raise notice 'on the copy: Ryanair''s four early cuts (BRI–CDG, CDG–SOF, CDG–SPU, CDG–VLC): % found, % off before, % after; % direction(s) with fares more than 1%% apart on their baseline day',
    cuts_found, coalesce(cuts_old_off::text, 'not saved'), cuts_new_off, n_mixed;
end
$test$;

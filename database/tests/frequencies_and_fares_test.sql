-- New frequencies and the fare ladder, on the copy (migration 20261021230000_frequencies_and_fares.sql; spec
-- docs/specs/2026-10-21-frequencies-and-fares.md §3: "show the counts of mismatches before and after on the rehearsal's
-- copy"). Run by database/rehearse.sh on the copy of last night's backup, after the new migrations, inside a transaction
-- that is rolled back; the hand-made cases are in fare_ladder_test.sql. Counts and route ids only, never rows.
--   1. Our routes and cabins off their level by the old index (the latest captured fare against the first, times the
--      launch level: database/tests/before/frequencies_and_fares_before.sql saved it before the changes) and by the new
--      one (each flight of the latest captured day against its direction's fare on 21 Oct 2026, when every route was at
--      its launch level), and how many get a set-back change (the route ids of those off, to look at).
--   2. Ryanair's four early cuts (BRI–CDG, CDG–SOF, CDG–SPU, CDG–VLC): off before; after, each read against its own
--      21 Oct fare (or the market's default price, since 4 Nov), and any still off caught by the ladder (set back, or on
--      this week's fare plan). Until 9 Nov this said "none off after", which held on 21 Oct's data. It stopped holding
--      when the ladder moved on: CDG–SPU stepped up to 90% on 2 Nov, and the game still showed 125 (85%) on the copy's
--      latest captured days (4 and 5 Nov), the raise reaching the game only by 8 Nov (132, 89.8%). The index was right
--      to call both directions off, and the ladder marked them to be set back ("captured fare at 85%, level 90%"); that
--      is the index doing its job, not the early cuts misread. What the spec's check proves still holds and is checked.
--   3. How many directions had flights more than 1% apart on their baseline day (where every route at its launch level
--      would have them all the same): a new flight the game priced at the default price shows here.
--   4. The fare ladder per direction (since 26 Oct; spec docs/specs/2026-10-26-fare-ladder-per-direction.md §4): each
--      route and cabin's two directions at the level the route had before the change (saved by the same file), so nothing
--      moves on day one. Since then the ladder's rows, and the counts in 1, are per direction.
create temporary table t_fl_new (airline_id bigint, iata text, route_id bigint, hub text, dest text, direction text, cabin text, fare_index numeric,
                                 index_matches boolean, fix boolean, level numeric, baseline_on date, default_source text, plan_id bigint) on commit drop;
do $test$
declare w bigint := private.fig_world(null); n_new int := 0; n_off int := 0; n_fix int := 0; n_old int; n_old_all int; ids text;
  cuts_found int := 0; cuts_old_off int; cuts_new_off int := 0; cuts_not_base int := 0; cuts_unnoticed int := 0; cuts_off text;
  n_mixed int; al record; d jsonb;
begin
  for al in select x.airline_id, a.iata_code from private.fig_airlines(w) x join public.airlines a on a.id = x.airline_id order by x.ord loop
    d := private.fig_fare_ladder(al.airline_id, now());
    insert into t_fl_new
    select al.airline_id, al.iata_code, (e ->> 'route_id')::bigint, e ->> 'hub', e ->> 'dest', e ->> 'direction', e ->> 'cabin', (e ->> 'fare_index')::numeric,
           (e ->> 'index_matches')::boolean, (e ->> 'fix')::boolean, (e ->> 'level')::numeric, (e ->> 'baseline_on')::date,
           e ->> 'default_source', (e ->> 'plan_id')::bigint
      from jsonb_array_elements(d -> 'routes') e;
  end loop;
  select count(*), count(*) filter (where index_matches = false), count(*) filter (where fix) into n_new, n_off, n_fix from t_fl_new;
  -- Ryanair's four early cuts (spec part 3): BRI–CDG, CDG–SOF, CDG–SPU, CDG–VLC, either way round
  -- each is read against its 21 Oct fare (inferred) or the market's default; one off is set back or on this week's plan
  select count(*), count(*) filter (where n.index_matches = false),
         count(*) filter (where n.default_source is distinct from 'market' and n.baseline_on is distinct from date '2026-10-21'),
         count(*) filter (where n.index_matches = false and not coalesce(n.fix, false) and n.plan_id is null),
         string_agg(format('%s>%s at %s, level %s%s', case when n.direction = 'out' then n.hub else n.dest end,
                           case when n.direction = 'out' then n.dest else n.hub end, n.fare_index, n.level,
                           case when n.fix then ', set back' when n.plan_id is not null then ', on this week''s plan' else '' end), '; ')
           filter (where n.index_matches = false)
    into cuts_found, cuts_new_off, cuts_not_base, cuts_unnoticed, cuts_off
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
  assert cuts_not_base = 0, format('of Ryanair''s %s early cuts found, %s aren''t read against their 21 Oct fare or the market''s default', cuts_found, cuts_not_base);
  assert cuts_unnoticed = 0, format('of Ryanair''s %s early cuts found, %s are off their level by the new index and neither set back nor on this week''s plan (%s)',
    cuts_found, cuts_unnoticed, cuts_off);
  raise notice 'on the copy: % routes, directions and cabins; off their level by the old index (the latest fare against the first): % of %; by the new (each flight against its 21 Oct fare): % of %, % of them set back%',
    n_new, coalesce(n_old::text, 'not saved'), coalesce(n_old_all::text, '—'), n_off, n_new, n_fix, case when ids is null then '' else ' (route ids ' || ids || ')' end;
  raise notice 'on the copy: Ryanair''s four early cuts (BRI–CDG, CDG–SOF, CDG–SPU, CDG–VLC): % found, % off before, % after%, each read against its 21 Oct fare or the market''s default; % direction(s) with fares more than 1%% apart on their baseline day',
    cuts_found, coalesce(cuts_old_off::text, 'not saved'), cuts_new_off, case when cuts_off is null then '' else ' (' || cuts_off || ')' end, n_mixed;
end
$test$;

-- 4. the starting levels per direction (spec docs/specs/2026-10-26-fare-ladder-per-direction.md §4): each route and
-- cabin's directions at the level fare_ladder() gave it before the change (rehearsal_before.fare_index, saved by
-- database/tests/before/frequencies_and_fares_before.sql). A row saved before the ladder went per direction has none and
-- stands for both: each of its two directions now must be at its level; a row saved with a direction, its own.
do $test$
declare n_before int; n_rows int; n_off int; n_missing int; ids text;
begin
  if to_regclass('rehearsal_before.fare_index') is null or not exists (select 1 from rehearsal_before.fare_index) then
    raise notice 'on the copy: no fare ladder saved before the change: the starting levels weren''t compared';
    return;
  end if;
  with b as (select b.*, x.dir from rehearsal_before.fare_index b
               cross join lateral (select unnest(case when b.direction is null then array['out', 'back'] else array[b.direction] end) as dir) x),
       j as (select b.route_id, b.level as before_level, n.level, n.route_id is null as missing
               from b left join t_fl_new n on n.airline_id = b.airline_id and n.route_id = b.route_id and n.cabin = b.cabin and n.direction = b.dir)
  select (select count(*) from rehearsal_before.fare_index), count(*), count(*) filter (where not j.missing and j.level is distinct from j.before_level),
         count(*) filter (where j.missing), string_agg(distinct j.route_id::text, ', ') filter (where j.missing or j.level is distinct from j.before_level)
    into n_before, n_rows, n_off, n_missing, ids
    from j;
  assert n_off = 0 and n_missing = 0,
    format('of %s routes and cabins saved before the change, %s direction(s) don''t start at their level and %s are missing (route ids %s)', n_before, n_off, n_missing, coalesce(ids, '—'));
  raise notice 'on the copy, the starting levels: the % rows saved before the change give % directions, each now at the level it had (none moved, none missing)', n_before, n_rows;
end
$test$;

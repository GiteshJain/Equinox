-- Before the switch (decision #18, build pull request 12; migration 20261014180000_reference.sql). Run by
-- database/rehearse.sh on the copy of last night's backup, after the new migrations, inside a transaction that is rolled
-- back. A failed check stops with an error that says where (keys and counts only):
--   1. countries.region: described; every country the old planner's REGION_OF list names has its region; the unknown
--      country (--) is Other; every other country is Europe (the old fallback), and so is a country added later (the
--      column's default).
--   2. rules_input(): each airport carries its country's region, none for an airport with no country.
--   3. suggested_size: in every world as the old planner's code had it (bigSize, suggestSize, feedSize), with its unit,
--      description, since 14 Oct and reason; Ryanair's own for each Ryanair of ours; rules_input() gives the world's value
--      and, in Ryanair's settings, its own.
--   4. airlines.photo_city: each of our airlines has its city, described for Home's cards too.
--   (3 also: interline_rules, the old Interline screen's lists, in every world, carried by rules_input().)

-- ---------------------------------------------------------------- 1. regions
create temporary table t_rf_list on commit drop as
select r.region, unnest(string_to_array(r.codes, ' ')) as code
  from (values ('South Asia', 'IN PK BD LK NP MV BT AF'), ('China & North-East Asia', 'CN HK MO TW JP KR MN'),
               ('South-East Asia', 'MY SG TH VN KH LA MM BN ID PH TL'), ('Oceania', 'AU NZ FJ PG PF NC VU SB WS TO CK'),
               ('Middle East', 'AE QA OM BH KW SA TR IL JO LB IR IQ YE'), ('Russia & Central Asia', 'RU KZ UZ KG TJ TM AZ GE AM BY UA MD'),
               ('North America', 'US CA MX PM GL BM AG AI AW BB BQ BS CU CW DM DO GD GP HT JM KN KY LC MQ PR SX TC TT VC VI BZ CR GT HN NI PA SV'),
               ('South America', 'AR BO BR CL CO EC GF GY PE PY SR UY VE'),
               ('Africa', 'DZ EG LY MA TN AO BJ CD CG CI CM CV DJ ET GA GH GM GN GQ KE MG MR MU NA NG RE RW SC SN TD TG TZ UG YT ZA ZM ZW MZ BW SS SD SO')) as r(region, codes);

do $test$
declare n_listed int; n_other int; n_europe int; bad text;
begin
  assert col_description('public.countries'::regclass,
                         (select attnum from pg_attribute where attrelid = 'public.countries'::regclass and attname = 'region')) is not null,
    'countries.region has no description';
  select string_agg(c.code || ' ' || c.region, ', ') into bad
    from public.countries c left join pg_temp.t_rf_list l on l.code = c.code
   where c.region is distinct from coalesce(l.region, case when c.code = '--' then 'Other' else 'Europe' end);
  assert bad is null, 'these countries don''t have the old planner''s region: ' || bad;
  select count(*) into n_listed from public.countries c join pg_temp.t_rf_list l on l.code = c.code;
  select count(*) filter (where c.region = 'Other'), count(*) filter (where c.region = 'Europe') into n_other, n_europe from public.countries c;
  perform set_config('equinox.actor', 'claude', true), set_config('equinox.actor_detail', 'reference test', true);
  insert into public.countries (code, name) values ('Q1', 'A test country');
  assert (select region from public.countries where code = 'Q1') = 'Europe', 'a country added later doesn''t take Europe';
  delete from public.countries where code = 'Q1';
  perform set_config('equinox.actor', '', true), set_config('equinox.actor_detail', '', true);
  raise notice 'regions: % countries on the old list with its region, % Europe (the fallback), % Other; a country added later takes Europe', n_listed, n_europe, n_other;
end
$test$;

-- ---------------------------------------------------------------- 2. rules_input(): each airport's region
do $test$
declare doc jsonb := private.rules_input_doc(null, 'all'); bad text; n int;
begin
  select string_agg(e ->> 'code', ', '), count(*) into bad, n from jsonb_array_elements(doc -> 'airports') e
   where not e ? 'region'
      or (e ->> 'region') is distinct from (select c.region from public.airports a join public.countries c on c.code = a.country_code where a.code = e ->> 'code');
  assert bad is null, 'these airports don''t carry their country''s region in rules_input(): ' || bad;
  select count(*) into n from jsonb_array_elements(doc -> 'airports') e where e ->> 'region' is not null;
  raise notice 'rules_input(): each of the % airports carries its country''s region (% with one)', jsonb_array_length(doc -> 'airports'), n;
end
$test$;

-- ---------------------------------------------------------------- 3. the suggested size
do $test$
declare n_worlds int := (select count(*) from public.worlds); n_fr int; r record; doc jsonb;
  v_world jsonb := '{"big": [{"min_stars": 5, "type": "A321neo"}, {"type": "A320neo"}],
                     "freq": [{"min_stars": 5, "type": "A321neo"}, {"min_stars": 3, "type": "A320neo"}, {"type": "E195"}],
                     "feeder": [{"min_stars": 3, "over_km": 2500, "type": "A320neo"}, {"type": "E195"}]}';
  v_fr jsonb := '{"big": [{"type": "A321neo"}], "freq": [{"min_stars": 4, "type": "A321neo"}, {"type": "E195"}], "feeder": [{"type": "E195"}]}';
begin
  assert (select count(*) from public.settings s where s.key = 'suggested_size' and s.airline_id is null and s.value = v_world
            and s.unit = 'aircraft type by move' and s.since = date '2026-10-14' and s.description like '%suggestSize%'
            and s.reason like '%given a home of their own%') = n_worlds,
    'suggested_size isn''t the old planner''s sizes (since 14 Oct, described, with its reason) in every world';
  select count(*) into n_fr from public.airlines a join public.groups g on g.id = a.group_id and g.world_id = a.world_id and g.kind = 'ours'
   where a.planner_name = 'Ryanair';
  assert (select count(*) from public.settings s join public.airlines a on a.id = s.airline_id
           where s.key = 'suggested_size' and a.planner_name = 'Ryanair' and s.value = v_fr and s.description is not null) = n_fr,
    'Ryanair''s own suggested_size isn''t there for each Ryanair of ours';
  doc := private.rules_input_doc(null, 'flown');
  assert doc -> 'settings' -> 'suggested_size' = v_world, 'rules_input() doesn''t carry the world''s suggested_size';
  for r in select a from jsonb_array_elements(doc -> 'airlines') a where a ->> 'planner_name' = 'Ryanair' loop
    assert r.a -> 'settings' -> 'suggested_size' = v_fr, 'rules_input() doesn''t give Ryanair its own suggested_size';
  end loop;
  for r in select a from jsonb_array_elements(doc -> 'airlines') a where a ->> 'planner_name' <> 'Ryanair' and (a ->> 'ours')::boolean loop
    assert r.a -> 'settings' -> 'suggested_size' = v_world, 'rules_input() doesn''t give ' || (r.a ->> 'iata_code') || ' the world''s suggested_size';
  end loop;
  assert (select count(*) from public.settings s where s.key = 'interline_rules' and s.airline_id is null
            and s.value ?& array['countries', 'europe_zone', 'rivals', 'covered', 'group_only', 'partners']
            and (select count(*) from jsonb_object_keys(s.value -> 'countries')) = 17
            and s.since = date '2026-10-14' and s.description like '%IL_YES%' and s.reason is not null) = n_worlds,
    'interline_rules isn''t the old Interline screen''s lists (17 countries, since 14 Oct, described) in every world';
  assert doc -> 'settings' ? 'interline_rules', 'rules_input() doesn''t carry interline_rules';
  raise notice 'suggested_size: the old sizes in each of the % world(s), Ryanair''s own (% airline(s)); rules_input() gives each airline its own; interline_rules: the 17 interline countries and the lists, in each world', n_worlds, n_fr;
end
$test$;

-- ---------------------------------------------------------------- 4. the airline cards' photos
do $test$
declare bad text;
begin
  select string_agg(coalesce(a.iata_code, a.id::text), ', ') into bad
    from public.airlines a join public.groups g on g.id = a.group_id and g.world_id = a.world_id and g.kind = 'ours'
   where a.planner_name in ('Pan American', 'Virgin Atlantic', 'Ryanair', 'Kingfisher', 'China Eastern', 'Malaysia Airlines')
     and coalesce(a.photo_city, '') = '';
  assert bad is null, 'these airlines of ours have no photo city: ' || bad;
  assert col_description('public.airlines'::regclass,
                         (select attnum from pg_attribute where attrelid = 'public.airlines'::regclass and attname = 'photo_city')) like '%Home%',
    'airlines.photo_city''s description doesn''t mention Home''s cards';
  raise notice 'photo cities: every one of our six airlines has its city';
end
$test$;

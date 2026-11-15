-- The fares userscript's own limit (15 Nov 2026; to-do 247 with to-do 218 step 3; spec
-- docs/specs/2026-11-15-self-updating-scripts.md §8; migration 20261115170000_fares_script_limit.sql). Run by
-- database/rehearse.sh on the copy of last night's backup, after the new migrations, inside a transaction that is rolled
-- back. A failed check stops with an error that says which (keys, codes and numbers, never rows).
--   1. The two settings, fares_script_min_pct and fares_script_max_pct, are in every world as world rows: numbers, the
--      lower under the upper, described, with their unit; on the default world (Gander) 55 and 135.
--   2. The fare ladder can't reach them (the cap-reaches-limit check): for every active airline of ours in every world
--      with the rows, its highest level (fare_launch_pct plus fare_ladder_cap_pts, its own rows where it has them) is
--      under fares_script_max_pct, and its lowest (the smaller of world_rules.fare_floor_pct and the last of its
--      fare_under_launch_levels) over fares_script_min_pct. A cap or floor changed to reach the limit turns this red:
--      move the limit in the same rule change (manual §1 and §5).
--   3. capture_fare_actions_by_airline(), signed out with a key of the default world, as the userscript (1.5) calls it:
--      the list answers limits {min_pct, max_pct} equal to the two rows; with one row gone, limits is null (the
--      userscript then refuses the plan); each airline's own answer is as before (no limits in it).

create temporary table t_fl (k text primary key, v jsonb) on commit drop;
grant select, insert on t_fl to anon, authenticated;

-- ---------------------------------------------------------------- 1. the two settings
do $test$
declare w record; lo jsonb; hi jsonb; n int := 0; d bigint := (select id from public.worlds where is_default);
begin
  for w in select id, name from public.worlds loop
    select s.value into lo from public.settings s where s.world_id = w.id and s.airline_id is null and s.key = 'fares_script_min_pct';
    select s.value into hi from public.settings s where s.world_id = w.id and s.airline_id is null and s.key = 'fares_script_max_pct';
    assert lo is not null and hi is not null, 'world ' || w.id || ' has no fares_script_min_pct or fares_script_max_pct row';
    assert jsonb_typeof(lo) = 'number' and jsonb_typeof(hi) = 'number', 'world ' || w.id || ': a fares script limit isn''t a number';
    assert (lo #>> '{}')::numeric < (hi #>> '{}')::numeric, 'world ' || w.id || ': the fares script''s lower limit isn''t under its upper';
    n := n + 1;
  end loop;
  assert not exists (select 1 from public.settings s where s.key in ('fares_script_min_pct', 'fares_script_max_pct')
                      and (coalesce(s.description, '') = '' or s.unit is distinct from '% of default price')),
    'a fares script limit row has no description or the wrong unit';
  assert not exists (select 1 from public.settings s where s.key in ('fares_script_min_pct', 'fares_script_max_pct') and s.airline_id is not null),
    'a fares script limit has an airline''s own row: it is one limit for the world';
  if d is not null then
    assert (select s.value from public.settings s where s.world_id = d and s.airline_id is null and s.key = 'fares_script_min_pct') = '55'::jsonb
       and (select s.value from public.settings s where s.world_id = d and s.airline_id is null and s.key = 'fares_script_max_pct') = '135'::jsonb,
      'the default world''s fares script limit isn''t 55% to 135%';
  end if;
  raise notice 'the fares script''s limit: two described world rows in each of % worlds, the default world''s 55%% to 135%%', n;
end
$test$;

-- ---------------------------------------------------------------- 2. the ladder can't reach the limit
do $test$
declare a record; lo numeric; hi numeric; top numeric; bottom numeric; floor_pct numeric; levels jsonb; seen int := 0;
  highest numeric; lowest numeric;
begin
  for a in select al.id, al.world_id, coalesce(al.iata_code, al.id::text) as code
             from public.airlines al join public.groups g on g.id = al.group_id and g.world_id = al.world_id
            where al.active and g.kind = 'ours' order by al.world_id, al.id loop
    select (s.value #>> '{}')::numeric into lo from public.settings s where s.world_id = a.world_id and s.airline_id is null and s.key = 'fares_script_min_pct';
    select (s.value #>> '{}')::numeric into hi from public.settings s where s.world_id = a.world_id and s.airline_id is null and s.key = 'fares_script_max_pct';
    continue when lo is null or hi is null;
    -- an airline without the ladder's settings has no ladder to reach anything
    continue when not exists (select 1 from public.settings s where s.world_id = a.world_id and s.key = 'fare_ladder_cap_pts')
               or not exists (select 1 from public.settings s where s.world_id = a.world_id and s.key = 'fare_launch_pct');
    top := private.fig_num(a.world_id, a.id, 'fare_launch_pct') + private.fig_num(a.world_id, a.id, 'fare_ladder_cap_pts');
    select (r.value #>> '{}')::numeric into floor_pct from public.world_rules r where r.world_id = a.world_id and r.key = 'fare_floor_pct';
    select s.value into levels from public.settings s
     where s.world_id = a.world_id and s.key = 'fare_under_launch_levels' and (s.airline_id is null or s.airline_id = a.id)
     order by s.airline_id nulls last limit 1;
    bottom := least(floor_pct, (select min((x #>> '{}')::numeric) from jsonb_array_elements(case when jsonb_typeof(levels) = 'array' then levels else '[]'::jsonb end) x));
    assert top < hi, 'the fare ladder can reach the fares script''s upper limit: airline ' || a.code || ' goes to ' || top
      || '% (fare_launch_pct + fare_ladder_cap_pts), the limit is ' || hi || '% (settings.fares_script_max_pct): move the limit with the cap (manual §5)';
    assert bottom is null or bottom > lo, 'the fare ladder can reach the fares script''s lower limit: airline ' || a.code || ' goes down to ' || bottom
      || '% (fare_floor_pct or fare_under_launch_levels), the limit is ' || lo || '% (settings.fares_script_min_pct): move the limit with the floor (manual §5)';
    highest := greatest(highest, top); lowest := least(lowest, bottom); seen := seen + 1;
  end loop;
  raise notice 'the fare ladder stays inside the fares script''s limit: % airlines of ours, highest level %, lowest %', seen, coalesce(highest || '%', '-'), coalesce(lowest || '%', '-');
end
$test$;

-- ---------------------------------------------------------------- 3. the list answers the limits
do $setup$
begin
  insert into public.capture_keys (label, key_hash, world_id)
  select 'fares script limit test', extensions.crypt('fares-limit-test-key', extensions.gen_salt('bf')), w.id
    from public.worlds w where w.is_default;
end
$setup$;

set local role anon;
do $test$
declare l jsonb; one jsonb;
begin
  l := public.capture_fare_actions_by_airline('fares-limit-test-key');
  insert into t_fl values ('list', l);
  if jsonb_array_length(coalesce(l -> 'airlines', '[]'::jsonb)) > 0 then
    one := public.capture_fare_actions_by_airline('fares-limit-test-key', (l -> 'airlines' -> 0 ->> 'game_id')::int);
    insert into t_fl values ('one', one);
  end if;
end
$test$;
reset role;

do $test$
declare l jsonb := (select v from t_fl where k = 'list'); one jsonb := (select v from t_fl where k = 'one');
  d bigint := (select id from public.worlds where is_default);
begin
  if d is null then raise notice 'no default world on the copy: the list''s limits weren''t checked'; return; end if;
  assert l ->> 'ok' = 'true', 'the default world''s list didn''t answer: ' || coalesce(l ->> 'error', 'no error');
  assert l -> 'limits' = jsonb_build_object('min_pct', 55, 'max_pct', 135),
    'the list doesn''t answer the fares script''s limits from the settings: ' || coalesce((l -> 'limits')::text, 'none');
  assert one is null or (one ->> 'ok' = 'true' and not one ? 'limits'), 'an airline''s own answer changed: ' || coalesce(one ->> 'error', 'it has limits');
  delete from public.settings s where s.world_id = d and s.airline_id is null and s.key = 'fares_script_max_pct';
end
$test$;

set local role anon;
do $test$
begin
  insert into t_fl values ('list_without', public.capture_fare_actions_by_airline('fares-limit-test-key'));
end
$test$;
reset role;

do $test$
declare l jsonb := (select v from t_fl where k = 'list_without');
begin
  if l is null then return; end if;
  assert l ->> 'ok' = 'true' and l ? 'limits' and jsonb_typeof(l -> 'limits') = 'null',
    'with fares_script_max_pct gone the list doesn''t answer limits null: ' || coalesce((l -> 'limits')::text, 'no limits key');
  raise notice 'capture_fare_actions_by_airline(): the list answers limits 55 to 135 from the settings, null with a row gone; an airline''s answer has none';
end
$test$;

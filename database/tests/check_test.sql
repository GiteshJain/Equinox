-- The Check screen's database parts (decision #18, build pull request 9; migration 20261013235900_check.sql). Run by
-- database/rehearse.sh on the copy of last night's backup, after the new migrations, inside a transaction that is rolled
-- back. A failed check stops with an error that says where (keys and counts only). Nothing on the copy changes:
--   1. The settings the old Check kept in its code, in every world with the old planner's numbers, each with its unit, its
--      description, since 13 Oct and its reason: growth_big_min_stars 4, growth_ready_min_days 5, growth_ready_full_share
--      0.95, order_queue_grace_h 6 and order_queue_warn_h 48. (The other two, cabin_refit_cost and cabin_refit_share_pct,
--      went with the Cabins board on 21 Oct, migration 20261021180000; database/tests/cabins_new_rule_test.sql checks
--      they're gone.)
--   2. rules_input() carries each, as the planning library reads them.

-- ---------------------------------------------------------------- 1. the settings
do $test$
declare n_worlds int := (select count(*) from public.worlds); r record; doc jsonb;
begin
  for r in select * from (values
      ('growth_big_min_stars', '4'::jsonb, 'stars', 'moveCandidates'),
      ('growth_ready_min_days', '5'::jsonb, 'reported days', 'moveCandidates'),
      ('growth_ready_full_share', '0.95'::jsonb, 'share of departures', 'moveCandidates'),
      ('order_queue_grace_h', '6'::jsonb, 'hours', 'growthBoard'),
      ('order_queue_warn_h', '48'::jsonb, 'hours', 'growthBoard')) as x(key, value, unit, old) loop
    assert (select count(*) from public.settings s where s.key = r.key and s.airline_id is null and s.value = r.value and s.unit = r.unit
              and s.since = date '2026-10-13' and s.description like '%' || r.old || '%' and s.reason like '%given a home of its own%') = n_worlds,
      format('%s isn''t %s (%s, since 13 Oct, described with %s and its reason) in every world', r.key, r.value, r.unit, r.old);
    doc := private.rules_input_doc(null, 'flown');
    assert doc -> 'settings' -> r.key = r.value, format('rules_input() doesn''t carry %s', r.key);
  end loop;
  raise notice 'the five settings the old Check kept in its code that stay: in each of the % world(s) with its number, unit, description, since 13 Oct and reason; rules_input() carries them', n_worlds;
end
$test$;

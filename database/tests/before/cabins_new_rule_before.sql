-- Saved by database/rehearse.sh before the pending changes run, into the schema rehearsal_before, and compared afterwards
-- by database/tests/cabins_new_rule_test.sql (spec docs/specs/2026-10-21-cabins-new-rule.md §2): each market's default
-- cabin layout (its code and cabin) and its airline's kind, while markets still has default_config_id, so the test can
-- show each market's layout is its old default's cabin; and how many "keep as is" rows there were, which stay as history.
-- Once 20261021180000_cabins_new_rule.sql is live the column is gone, and the tables are left empty (the test then checks
-- what still holds).
create table rehearsal_before.market_layouts (market_id bigint, airline_id bigint, config_code text, config_cabin text, is_lcc boolean);
create table rehearsal_before.cabin_keeps (n bigint);

do $save$
begin
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'markets' and column_name = 'default_config_id') then
    execute $q$
      insert into rehearsal_before.market_layouts (market_id, airline_id, config_code, config_cabin, is_lcc)
      select m.id, m.airline_id, c.code, c.cabin, coalesce(al.is_lcc, false)
        from public.markets m
        left join public.cabin_configs c on c.id = m.default_config_id
        left join public.airlines al on al.id = m.airline_id
    $q$;
  end if;
end
$save$;

insert into rehearsal_before.cabin_keeps (n) select count(*) from public.aircraft_cabin_keeps;

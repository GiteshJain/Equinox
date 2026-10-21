-- Cabins follow the new rule (manual §5; migration 20261021180000_cabins_new_rule.sql; spec
-- docs/specs/2026-10-21-cabins-new-rule.md). Run by database/rehearse.sh on the copy of last night's backup, after the new
-- migrations, inside a transaction that is rolled back. A failed check stops with an error that says where (ids, codes
-- and counts, never rows).
--   1. The settings: cabin_refit_cost and cabin_refit_share_pct are gone from every world and airline;
--      cabin_route_share_pct is 65 in every world, with its unit, description, since 20 Oct and reason, and rules_input()
--      carries it.
--   2. markets keeps only its layout: default_type_id, default_config_id, fare_y_pct and fare_j_pct are gone; layout is
--      there, not null, checked to Standard, Leisure, Leisure Plus or Comfort, and described, and so is the table. Every
--      market has a layout.
--   3. Each market's layout is the cabin of its old default layout (database/tests/before/cabins_new_rule_before.sql), as
--      the spec lists them: every -LP Leisure Plus, -CMF Comfort, -LEI Leisure, -STD Standard; a low-cost airline's
--      markets (Ryanair's) are Standard. On a copy where the change was already live there is no before, and only the
--      low-cost rule is checked. The count of each layout is printed.
--   4. aircraft_cabin_keeps is kept with as many rows as before, described as retired.
--   5. rules_input() carries each layout's name (cabin_configs.cabin), each airline's is_lcc, and each route's
--      market_layout (its market's, any override applied) and own cabin_choice, all as the tables have them.
--   6. The briefing (private.briefing_doc()) gives each plan card its config_id, as plan_cards has it.
--   7. No function in public or private names the dropped columns.
--   8. A layout outside the four is refused; Reference's change of a market's layout, through planner_save() as staff,
--      is saved and logged as planner with the tab.

create temporary table t_cnr (k text primary key, v jsonb) on commit drop;
grant select, insert, update on t_cnr to authenticated;
insert into public.planner_users (email) values ('cabins-new-rule-test-staff@example.com') on conflict do nothing;

-- ---------------------------------------------------------------- 1. the settings
do $test$
declare n_worlds int := (select count(*) from public.worlds); doc jsonb := private.rules_input_doc(null, 'all');
begin
  assert not exists (select 1 from public.settings s where s.key in ('cabin_refit_cost', 'cabin_refit_share_pct')),
    'a refit setting (cabin_refit_cost or cabin_refit_share_pct) is still there';
  assert (select count(*) from public.settings s where s.key = 'cabin_route_share_pct' and s.airline_id is null and s.value = '65'::jsonb
            and s.unit = 'percent of block time' and s.since = date '2026-10-20' and s.description like '%more than this share%'
            and s.reason like 'Gitesh, 20 Oct%') = n_worlds,
    'cabin_route_share_pct isn''t 65 (percent of block time, since 20 Oct, described with its reason) in every world';
  assert doc -> 'settings' -> 'cabin_route_share_pct' = '65'::jsonb, 'rules_input() doesn''t carry cabin_route_share_pct';
  assert not (doc -> 'settings' ? 'cabin_refit_cost') and not (doc -> 'settings' ? 'cabin_refit_share_pct'), 'rules_input() still carries a refit setting';
  raise notice 'the settings: both refit settings gone; cabin_route_share_pct 65 in each of the % world(s), described, and in rules_input()', n_worlds;
end
$test$;

-- ---------------------------------------------------------------- 2. markets keeps only its layout
do $test$
declare v_gone text; v_def text;
begin
  select string_agg(c.column_name, ', ' order by c.column_name) into v_gone from information_schema.columns c
   where c.table_schema = 'public' and c.table_name = 'markets' and c.column_name in ('default_type_id', 'default_config_id', 'fare_y_pct', 'fare_j_pct');
  assert v_gone is null, 'these columns of markets are still there: ' || v_gone;
  assert exists (select 1 from information_schema.columns c where c.table_schema = 'public' and c.table_name = 'markets' and c.column_name = 'layout'
                   and c.data_type = 'text' and c.is_nullable = 'NO'), 'markets.layout isn''t a text column that must be filled';
  select pg_get_constraintdef(x.oid) into v_def from pg_constraint x where x.conrelid = 'public.markets'::regclass and x.conname = 'markets_layout_check';
  assert v_def like '%Standard%' and v_def like '%''Leisure''%' and v_def like '%Leisure Plus%' and v_def like '%Comfort%',
    'markets.layout isn''t checked to Standard, Leisure, Leisure Plus or Comfort: ' || coalesce(v_def, 'no check');
  assert coalesce(col_description('public.markets'::regclass, (select a.attnum from pg_attribute a where a.attrelid = 'public.markets'::regclass and a.attname = 'layout')), '')
         like '%Standard, Leisure, Leisure Plus or Comfort%', 'markets.layout isn''t described';
  assert coalesce(obj_description('public.markets'::regclass, 'pg_class'), '') like '%keeps only its layout%', 'markets'' description doesn''t say it keeps only its layout';
  assert not exists (select 1 from public.markets m where m.layout is null or m.layout not in ('Standard', 'Leisure', 'Leisure Plus', 'Comfort')),
    'a market has no layout, or one that isn''t Standard, Leisure, Leisure Plus or Comfort';
  raise notice 'markets: default_type_id, default_config_id, fare_y_pct and fare_j_pct gone; layout there, not null, checked and described, for each of its % rows',
    (select count(*) from public.markets);
end
$test$;

-- ---------------------------------------------------------------- 3. each market's layout, from its old default
do $test$
declare n_before int := (select count(*) from rehearsal_before.market_layouts); v_bad text; v_counts text;
begin
  if n_before > 0 then
    select string_agg(b.market_id || ' (' || coalesce(b.config_code, 'no default') || ': ' || coalesce(m.layout, 'gone') || ')', ', ' order by b.market_id) into v_bad
      from rehearsal_before.market_layouts b left join public.markets m on m.id = b.market_id
     where m.id is null
        or m.layout is distinct from coalesce(b.config_cabin, case when b.is_lcc then 'Standard' end)
        or (b.config_code ~ '-LP\M' and m.layout <> 'Leisure Plus')
        or (b.config_code ~ '-CMF\M' and m.layout <> 'Comfort')
        or (b.config_code ~ '-LEI\M' and m.layout <> 'Leisure')
        or (b.config_code ~ '-STD\M' and m.layout <> 'Standard');
    assert v_bad is null, 'these markets'' layouts aren''t their old default''s cabin (-LP Leisure Plus, -CMF Comfort, -LEI Leisure, -STD Standard): ' || v_bad;
    assert (select count(*) from public.markets) = n_before, 'markets were added or removed';
  end if;
  select string_agg(m.id::text, ', ' order by m.id) into v_bad
    from public.markets m join public.airlines al on al.id = m.airline_id where al.is_lcc and m.layout <> 'Standard';
  assert v_bad is null, 'these low-cost airline''s markets aren''t Standard: ' || v_bad;
  select string_agg(x.layout || ' ' || x.n, ', ' order by x.layout) into v_counts
    from (select m.layout, count(*) as n from public.markets m group by m.layout) x;
  raise notice 'each market''s layout: %', case when n_before > 0 then 'its old default''s cabin, for all ' || n_before
                                                 else 'no before on this copy (already live), the low-cost airline''s Standard checked' end;
  raise notice 'markets by layout: %', coalesce(v_counts, 'none');
end
$test$;

-- ---------------------------------------------------------------- 4. the cabins kept as they are, as history
do $test$
declare n_before bigint := (select n from rehearsal_before.cabin_keeps limit 1);
begin
  assert to_regclass('public.aircraft_cabin_keeps') is not null, 'aircraft_cabin_keeps is gone';
  assert n_before is null or (select count(*) from public.aircraft_cabin_keeps) = n_before, 'aircraft_cabin_keeps lost or gained rows';
  assert coalesce(obj_description('public.aircraft_cabin_keeps'::regclass, 'pg_class'), '') like 'Retired 21 Oct%nothing writes to it%',
    'aircraft_cabin_keeps isn''t described as retired, with nothing writing to it';
  raise notice 'aircraft_cabin_keeps: kept as history (% rows), described as retired', (select count(*) from public.aircraft_cabin_keeps);
end
$test$;

-- ---------------------------------------------------------------- 5. the planning library's input carries the layouts
do $test$
declare doc jsonb := private.rules_input_doc(null, 'all'); w bigint := (select x.id from public.worlds x where x.is_default); v_bad text;
begin
  select string_agg(e ->> 'code', ', ') into v_bad from jsonb_array_elements(doc -> 'cabin_configs') e
   where not e ? 'cabin' or (e ->> 'cabin') is distinct from (select c.cabin from public.cabin_configs c where c.id = (e ->> 'id')::bigint);
  assert v_bad is null, 'rules_input()''s cabin layouts don''t carry their names (cabin): ' || v_bad;
  select string_agg(e ->> 'id', ', ') into v_bad from jsonb_array_elements(doc -> 'airlines') e
   where not e ? 'is_lcc' or (e -> 'is_lcc') <> to_jsonb(coalesce((select al.is_lcc from public.airlines al where al.id = (e ->> 'id')::bigint), false));
  assert v_bad is null, 'rules_input()''s airlines don''t carry is_lcc: ' || v_bad;
  select string_agg(e ->> 'id', ', ') into v_bad
    from jsonb_array_elements(doc -> 'routes') e join public.routes r on r.id = (e ->> 'id')::bigint
    left join public.markets m on m.id = case when r.market_cleared then null else coalesce(r.market_override_id, r.market_id) end
   where not (e ? 'market_layout' and e ? 'cabin_choice') or (e ->> 'market_layout') is distinct from m.layout
      or (e ->> 'cabin_choice') is distinct from r.cabin_choice;
  assert v_bad is null, 'rules_input()''s routes don''t carry their market''s layout and their own cabin choice: ' || v_bad;
  assert (select count(*) from jsonb_array_elements(doc -> 'routes')) = (select count(*) from public.routes r where r.world_id = w and not r.removed),
    'rules_input() lost routes';
  raise notice 'rules_input(): % cabin layouts with their names, % airlines with is_lcc, % routes with their market''s layout (% with one) and own cabin choice (% with one)',
    jsonb_array_length(doc -> 'cabin_configs'), jsonb_array_length(doc -> 'airlines'), jsonb_array_length(doc -> 'routes'),
    (select count(*) from jsonb_array_elements(doc -> 'routes') e where e ->> 'market_layout' is not null),
    (select count(*) from jsonb_array_elements(doc -> 'routes') e where e ->> 'cabin_choice' is not null);
end
$test$;

-- ---------------------------------------------------------------- 6. the briefing's plan cards carry their cabin
do $test$
declare r record; d jsonb; n int := 0; v_bad text;
begin
  for r in select distinct a.airline_id from public.aircraft a join public.plan_cards pc on pc.aircraft_id = a.id
            where a.status in ('on_order', 'delivered') loop
    d := private.briefing_doc(r.airline_id, now());
    select string_agg(c ->> 'id', ', ') into v_bad
      from jsonb_array_elements(d -> 'deliveries') x, jsonb_array_elements(x -> 'plan_cards') c
     where not c ? 'config_id' or (c -> 'config_id') is distinct from coalesce(to_jsonb((select pc.config_id from public.plan_cards pc where pc.id = (c ->> 'id')::bigint)), 'null'::jsonb);
    assert v_bad is null, format('airline %s: the briefing''s plan cards don''t carry their config_id: %s', r.airline_id, v_bad);
    n := n + (select count(*) from jsonb_array_elements(d -> 'deliveries') x, jsonb_array_elements(x -> 'plan_cards') c);
  end loop;
  raise notice 'the briefing: % plan card(s) of aircraft not yet filed, each with its config_id', n;
end
$test$;

-- ---------------------------------------------------------------- 7. nothing names the dropped columns
do $test$
declare v_bad text;
begin
  select string_agg(n.nspname || '.' || p.proname, ', ' order by n.nspname, p.proname) into v_bad
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'private') and p.prosrc ~ '\m(default_type_id|default_config_id|fare_y_pct|fare_j_pct)\M';
  assert v_bad is null, 'these functions name a dropped column of markets: ' || v_bad;
  select string_agg(v.table_name, ', ') into v_bad from information_schema.views v
   where v.table_schema in ('public', 'private') and v.view_definition ~ '\m(default_type_id|default_config_id|fare_y_pct|fare_j_pct)\M';
  assert v_bad is null, 'these views name a dropped column of markets: ' || v_bad;
  raise notice 'no function or view names default_type_id, default_config_id, fare_y_pct or fare_j_pct';
end
$test$;

-- ---------------------------------------------------------------- 8. the layout's check, and Reference's change of it
do $test$
declare m bigint := (select x.id from public.markets x order by x.id limit 1); refused boolean := false;
begin
  if m is null then
    raise notice 'the layout''s check: not tried (no market)';
    return;
  end if;
  begin
    update public.markets set layout = 'Economy' where id = m;
  exception when check_violation then refused := true;
  end;
  assert refused, 'a layout outside Standard, Leisure, Leisure Plus and Comfort was taken';
  insert into t_cnr values ('market', to_jsonb(m)), ('was', to_jsonb((select x.layout from public.markets x where x.id = m))),
    ('mark', to_jsonb(coalesce((select max(c.id) from public.change_log c), 0)));
  raise notice 'the layout''s check: Economy refused';
end
$test$;
do $$ begin perform set_config('request.jwt.claims',
  '{"sub": "00000000-0000-4000-8000-0000000000e8", "email": "cabins-new-rule-test-staff@example.com", "role": "authenticated"}', true); end $$;
set local role authenticated;
do $test$
declare m bigint := (select (v #>> '{}')::bigint from t_cnr where k = 'market'); was text := (select v #>> '{}' from t_cnr where k = 'was');
  want text; r jsonb; v_base timestamptz;
begin
  if m is null then return; end if;
  want := case when was = 'Comfort' then 'Leisure Plus' else 'Comfort' end;
  select x.updated_at into v_base from public.markets x where x.id = m;
  r := public.planner_save(jsonb_build_array(jsonb_build_object('table', 'markets', 'op', 'update', 'key', jsonb_build_object('id', m),
         'base', v_base, 'values', jsonb_build_object('layout', want))), 'cabins-new-rule-test');
  assert (r ->> 'ok')::boolean, 'planner_save() didn''t save a market''s layout: ' || r::text;
  assert (select x.layout from public.markets x where x.id = m) = want, 'the market''s layout wasn''t saved';
end
$test$;
reset role;
do $test$
declare mark bigint := (select (v #>> '{}')::bigint from t_cnr where k = 'mark'); got text;
begin
  if mark is null then return; end if;
  select string_agg(c.table_name || ' ' || c.op, ', ' order by c.id) into got
    from public.change_log c where c.id > mark and c.actor = 'planner' and c.actor_detail = 'cabins-new-rule-test';
  assert got = 'markets update', 'planner_save()''s change of a market''s layout wasn''t logged as planner with the tab: ' || coalesce(got, 'nothing');
  raise notice 'Reference''s change of a market''s layout: saved through planner_save() as staff, logged as planner with the tab';
end
$test$;

do $$ begin raise notice 'cabins follow the new rule: all checks passed'; end $$;

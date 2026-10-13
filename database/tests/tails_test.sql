-- The Tails screen's database parts (decision #18, build pull request 7; migration 20261013230000_tails.sql). Run by
-- database/rehearse.sh on the copy of last night's backup, after the new migrations, inside a transaction that is rolled
-- back. A failed check stops with an error that says where (codes, ids and counts only). Nothing on the copy changes:
--   1. order_cabin(): stable, run as owner with an empty search path, described; signed out it can't be called, signed
--      in it can; its builder (private.fig_order_cabin) stays internal.
--   2. For every one of our airlines and every aircraft type in its world, order_cabin() gives the layout
--      private.fig_order_cabin() picks (the one home of the old DEFAULT_CABIN), with that layout's code, cabin, cost and
--      type; null where it picks none. A type the airline may buy (airline_aircraft_types) has one.
--   3. The setting aircraft_block_target_h: 10 block hours a day in every world, described, since 13 Oct with its reason;
--      rules_input() carries it.
--   4. Signed out and an account that isn't staff are refused order_cabin(); staff get what postgres gets.

create temporary table t_tt (k text primary key, v jsonb) on commit drop;
grant select, insert, update on t_tt to authenticated, anon;
insert into public.planner_users (email) values ('tails-test-staff@example.com') on conflict do nothing;

-- ---------------------------------------------------------------- 1. who may call order_cabin()
do $test$
begin
  assert (select p.prosecdef and p.provolatile = 's' and coalesce('search_path=""' = any (p.proconfig), false) from pg_proc p
           where p.oid = 'public.order_cabin(bigint, bigint)'::regprocedure), 'order_cabin() isn''t stable, run as owner with an empty search path';
  assert not has_function_privilege('anon', 'public.order_cabin(bigint, bigint)', 'execute'), 'signed out, order_cabin() can be called';
  assert has_function_privilege('authenticated', 'public.order_cabin(bigint, bigint)', 'execute'), 'signed in, order_cabin() can''t be called';
  assert obj_description('public.order_cabin(bigint, bigint)'::regprocedure, 'pg_proc') like '%DEFAULT_CABIN%', 'order_cabin() has no description';
  assert not has_function_privilege('authenticated', 'private.fig_order_cabin(bigint, bigint)', 'execute'), 'order_cabin()''s builder can be called from outside';
  raise notice 'who may call order_cabin(): signed in only, stable, as owner with an empty search path, described; its builder internal';
end
$test$;

-- ---------------------------------------------------------------- 2. the answers on the copy
do $test$
declare n_pairs int := 0; n_cabins int := 0; n_buy int := 0; r record; got jsonb; want bigint; c record;
begin
  for r in select a.id as airline_id, a.iata_code, t.id as type_id, t.name,
                  exists (select 1 from public.airline_aircraft_types x where x.airline_id = a.id and x.aircraft_type_id = t.id) as may_buy
             from public.airlines a
             join public.groups g on g.id = a.group_id and g.world_id = a.world_id and g.kind = 'ours'
             join public.aircraft_types t on t.world_id = a.world_id
            order by a.id, t.id loop
    n_pairs := n_pairs + 1;
    got := public.order_cabin(r.airline_id, r.type_id);
    want := private.fig_order_cabin(r.airline_id, r.type_id);
    if want is null then
      assert got is null, format('order_cabin(%s, %s) gives %s where fig_order_cabin() picks none', r.iata_code, r.name, got);
      continue;
    end if;
    select cc.id, cc.code, cc.cabin, cc.cost, cc.aircraft_type_id into c from public.cabin_configs cc where cc.id = want;
    assert got is not null and (got ->> 'id')::bigint = c.id and got ->> 'code' is not distinct from c.code
           and got ->> 'cabin' is not distinct from c.cabin and (got ->> 'cost')::numeric is not distinct from c.cost
           and (got ->> 'aircraft_type_id')::bigint is not distinct from c.aircraft_type_id,
      format('order_cabin(%s, %s) isn''t layout %s as fig_order_cabin() picks it', r.iata_code, r.name, c.code);
    n_cabins := n_cabins + 1;
    if r.may_buy then n_buy := n_buy + 1; end if;
  end loop;
  assert n_pairs > 0, 'the copy has none of our airlines or no aircraft type';
  assert not exists (select 1 from public.airline_aircraft_types x join public.airlines a on a.id = x.airline_id
                      join public.groups g on g.id = a.group_id and g.kind = 'ours'
                     where private.fig_order_cabin(x.airline_id, x.aircraft_type_id) is null),
    'a type one of our airlines may buy has no order cabin';
  raise notice 'order_cabin() equals fig_order_cabin() for % airline-and-type pairs (% with a layout, every one of the % types an airline may buy among them)',
    n_pairs, n_cabins, n_buy;
end
$test$;

-- ---------------------------------------------------------------- 3. the setting
do $test$
declare n_worlds int := (select count(*) from public.worlds); doc jsonb;
begin
  assert (select count(*) from public.settings s where s.key = 'aircraft_block_target_h' and s.airline_id is null and s.value = '10'::jsonb
            and s.unit = 'block hours a day' and s.since = date '2026-10-13' and s.description like '%tailIssues%' and s.reason like '%10 h%') = n_worlds,
    'aircraft_block_target_h isn''t 10 (block hours a day, since 13 Oct, with its reason) in every world';
  doc := private.rules_input_doc(null, 'flown');
  assert doc -> 'settings' -> 'aircraft_block_target_h' = '10'::jsonb, 'rules_input() doesn''t carry aircraft_block_target_h';
  raise notice 'the setting: aircraft_block_target_h 10 block hours a day in each of the % world(s), described, since 13 Oct with its reason; rules_input() carries it', n_worlds;
end
$test$;

-- ---------------------------------------------------------------- 4. who is refused
insert into t_tt
select 'pair', jsonb_build_object('a', a.id, 't', x.aircraft_type_id)
  from public.airline_aircraft_types x join public.airlines a on a.id = x.airline_id
  join public.groups g on g.id = a.group_id and g.kind = 'ours'
 order by a.id, x.aircraft_type_id limit 1;

set local role anon;
do $test$
declare refused boolean := false;
begin
  begin perform public.order_cabin(1, 1); exception when insufficient_privilege then refused := true; end;
  assert refused, 'signed out, order_cabin() wasn''t refused';
end
$test$;
reset role;

do $$ begin perform set_config('request.jwt.claims',
  '{"sub": "00000000-0000-4000-8000-0000000000e1", "email": "tails-test-other@example.com", "role": "authenticated"}', true); end $$;
set local role authenticated;
do $test$
declare refused boolean := false;
begin
  begin perform public.order_cabin(1, 1); exception when insufficient_privilege then refused := true; end;
  assert refused, 'an account that isn''t staff wasn''t refused order_cabin()';
end
$test$;
reset role;

do $$ begin perform set_config('request.jwt.claims',
  '{"sub": "00000000-0000-4000-8000-0000000000e2", "email": "tails-test-staff@example.com", "role": "authenticated"}', true); end $$;
set local role authenticated;
do $test$
declare p jsonb := (select v from t_tt where k = 'pair');
begin
  if p is not null then
    insert into t_tt values ('staff', coalesce(public.order_cabin((p ->> 'a')::bigint, (p ->> 't')::bigint), 'null'::jsonb));
  end if;
end
$test$;
reset role;
do $test$
declare p jsonb := (select v from t_tt where k = 'pair');
begin
  assert p is null or (select v from t_tt where k = 'staff') = coalesce(public.order_cabin((p ->> 'a')::bigint, (p ->> 't')::bigint), 'null'::jsonb),
    'staff don''t get what postgres gets from order_cabin()';
  raise notice 'signed out and an account that isn''t staff are refused order_cabin(); staff get what postgres gets';
end
$test$;

-- The cabin charge check (manual §4: filing fits the plan card's cabin and logs its first fit at its price; migration
-- 20261022010000_tidy_ups.sql; spec docs/specs/2026-10-21-tidy-ups.md §3). Run by database/rehearse.sh on the copy of last
-- night's backup, after the new migrations, inside a transaction that is rolled back. A failed check stops with an error
-- that says which (codes, registrations and counts of the hand-made world only; on the copy, counts and registrations).
--   1. Who may call what: cabin_charges() signed in only, stable, as owner with an empty search path, described; its
--      builder private.fig_cabin_charges() and private.payment_aircraft() internal, with an empty search path, described;
--      the setting cabin_charge_check_from '2026-10-18' in every world, in days' date, described.
--   2. On the copy (the pull request's numbers): the cabin installation lines with their registration and aircraft (the
--      migration filled them), the pilot-training lines beside them; cabin_charges()'s counts by state and how long it
--      took, the problems by state with their registrations, and how the game's line fell against the day each matched fit
--      was logged.
--   3. A world of its own (our airline CQ, its setting moved to 2099-03-01), its statement folded by the capture's own
--      fold (private.fold_statement()): each installation line gets its registration and aircraft, pilot training
--      neither. One fit of each state: matches (CQ-001), differs (CQ-002, 97,000 against 99,000), charged twice
--      (CQ-003), not charged yet (CQ-004, logged 4 days before the latest statement line), waiting (CQ-005, 1.5 days),
--      not logged (CQ-006, a line and no fit at all). The setting's day respected: a fit logged before it (CQ-007) isn't
--      checked, and its line after the day isn't "not logged"; a line before the day with no fit (CQ-008) isn't listed.
--      Pilot training, beside every installation, is never a charge. A refit row (kind cabin, not a first fit) is no fit.
--   4. Use the game's amount: the differing fit's amount changed through planner_save() as staff, from the figure's
--      updated_at, logged as planner; then it matches. Signed out and an account that isn't staff are refused; staff get
--      what postgres gets.

create temporary table t_cc (k text primary key, v jsonb) on commit drop;
grant select, insert, update on t_cc to authenticated, anon;
insert into public.planner_users (email) values ('cabin-charges-staff@example.com') on conflict do nothing;

-- ---------------------------------------------------------------- 1. who may call what, and the setting
do $test$
declare f text := 'public.cabin_charges(timestamptz)'; g text; n_worlds int := (select count(*) from public.worlds);
begin
  assert (select p.prosecdef and p.provolatile = 's' and coalesce('search_path=""' = any (p.proconfig), false) from pg_proc p where p.oid = f::regprocedure),
    f || ' isn''t stable, run as owner with an empty search path';
  assert not has_function_privilege('anon', f, 'execute'), 'signed out, ' || f || ' can be called';
  assert has_function_privilege('authenticated', f, 'execute'), 'signed in, ' || f || ' can''t be called';
  assert not exists (select 1 from pg_proc p cross join aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                      where p.oid = f::regprocedure and a.grantee = 0), f || ' is open to public';
  assert length(coalesce(obj_description(f::regprocedure, 'pg_proc'), '')) > 400, f || ' has no description';
  foreach g in array array['private.fig_cabin_charges(bigint, timestamptz)', 'private.payment_aircraft(bigint, bigint, text)'] loop
    assert not has_function_privilege('authenticated', g, 'execute') and not has_function_privilege('anon', g, 'execute'), g || ' can be called from outside';
    assert (select not p.prosecdef and p.provolatile = 's' and coalesce('search_path=""' = any (p.proconfig), false) from pg_proc p where p.oid = g::regprocedure),
      g || ' runs as owner, isn''t stable or has no empty search path';
    assert length(coalesce(obj_description(g::regprocedure, 'pg_proc'), '')) > 60, g || ' has no description';
  end loop;
  assert (select count(*) from public.settings s where s.key = 'cabin_charge_check_from' and s.airline_id is null and s.value = '"2026-10-18"'::jsonb
            and s.unit = 'date' and s.description like '%the first day the plan card chose the cabin; earlier fits include refits%'
            and s.since = date '2026-10-21' and s.reason is not null) = n_worlds,
    'cabin_charge_check_from isn''t 2026-10-18 in every world, described, since 21 Oct, with its reason';
  -- the registration the game's cabin installation names, and nothing new for any other line
  assert private.payment_registration('Installation of cabin interior (9M-AAV)') = '9M-AAV'
     and private.payment_registration('Installation of cabin interior (N019AW)') = 'N019AW'
     and private.payment_registration('Installation of cabin interior (B-1234)') = 'B-1234'
     and private.payment_registration('Leasing rate for B-0161') = 'B-0161'
     and private.payment_registration('Pilot training') is null
     and private.payment_registration('Something else (G-AADR)') is null,
    'private.payment_registration() doesn''t read "Installation of cabin interior (<reg>)", or reads a registration in brackets elsewhere';
  raise notice 'cabin_charges(): signed in only, stable, as owner with an empty search path, described; fig_cabin_charges() and payment_aircraft() internal; cabin_charge_check_from 2026-10-18 in each of the % world(s), described; "Installation of cabin interior (<reg>)" names its registration', n_worlds;
end
$test$;

-- ---------------------------------------------------------------- 2. the copy (counts and registrations only)
do $test$
declare dw bigint := (select id from public.worlds where is_default); d jsonb; t0 timestamptz; ms int; c jsonb;
  n_inst int; n_reg int; n_ac int; n_train int; n_train_named int; v_states text; v_gap text;
begin
  select count(*) filter (where p.descr ilike 'Installation of cabin interior%'),
         count(*) filter (where p.descr ilike 'Installation of cabin interior%' and p.registration is not null),
         count(*) filter (where p.descr ilike 'Installation of cabin interior%' and p.aircraft_id is not null),
         count(*) filter (where p.descr ilike '%training%'),
         count(*) filter (where p.descr ilike '%training%' and (p.registration is not null or p.aircraft_id is not null))
    into n_inst, n_reg, n_ac, n_train, n_train_named
    from public.game_payments p where p.kind = 'cabin';
  -- (the shape of a line that doesn't read, letters and digits masked: never the line itself)
  assert n_reg = n_inst, format('%s of %s cabin installation lines have no registration; their shapes: %s', n_inst - n_reg, n_inst,
    (select string_agg(distinct regexp_replace(p.descr, '[A-Za-z0-9]', 'x', 'g'), ' | ') from public.game_payments p
      where p.kind = 'cabin' and p.descr ilike 'Installation of cabin interior%' and p.registration is null));
  assert n_train_named = 0, format('%s pilot-training lines name an aircraft', n_train_named);
  -- every installation line whose registration the airline has as an aircraft names that aircraft
  assert not exists (select 1 from public.game_payments p
                      where p.kind = 'cabin' and p.descr ilike 'Installation of cabin interior%' and p.aircraft_id is null
                        and exists (select 1 from public.aircraft ac where ac.world_id = p.world_id and ac.airline_id = p.airline_id
                                                                     and ac.registration = p.registration)),
    'an installation line names a registration the airline has, but not its aircraft';
  assert not exists (select 1 from public.game_payments p where p.aircraft_id is not null and p.descr not ilike 'Installation of cabin interior%'),
    'a line other than a cabin installation names an aircraft';
  raise notice 'on the copy: % cabin installation lines, each with its registration, % with its aircraft (the rest a registration the airline has no aircraft for); % pilot-training lines beside them, none naming an aircraft',
    n_inst, n_ac, n_train;

  t0 := clock_timestamp();
  d := private.fig_cabin_charges(dw, now());
  ms := round(extract(epoch from clock_timestamp() - t0) * 1000);
  c := d -> 'counts';
  select string_agg(x.state || ' ' || x.regs, '; ' order by x.state) into v_states
    from (select p ->> 'state' as state, string_agg(coalesce(p ->> 'code', '?') || ' ' || coalesce(p ->> 'registration', '?'), ', ' order by p ->> 'code', p ->> 'registration') as regs
            from jsonb_array_elements(d -> 'problems') p group by 1) x;
  raise notice 'on the copy, cabin charges since %: % fits checked, % match, % differ, % charged twice, % not charged yet, % waiting, % not logged (% problems), in % ms; %',
    d ->> 'check_from', c ->> 'checked', c ->> 'matches', c ->> 'differs', c ->> 'charged_twice', c ->> 'not_charged', c ->> 'waiting',
    c ->> 'not_logged', c ->> 'problems', ms, coalesce('the problems: ' || v_states, 'no problems');
  assert ms < 8000, format('cabin_charges() took %s ms on the copy: over the 8 s staff limit', ms);
  -- how the game's line falls against the day a matched fit was logged (00:00 UTC of spent_on), in hours: the check reads
  -- the lines from the setting's day, so a line the evening before the logged day still counts
  select format('%s matched fits: the game''s line from %s to %s hours after the logged day began (%s before it)',
                count(*), round(min(h)), round(max(h)), count(*) filter (where h < 0))
    into v_gap
    from (select extract(epoch from p.paid_at - (s.spent_on::timestamp at time zone 'UTC')) / 3600 as h
            from public.spending_log s
            join public.game_payments p on p.airline_id = s.airline_id and p.kind = 'cabin' and p.descr ilike 'Installation of cabin interior%'
                                       and p.registration = substring(s.note from '^(\S+) first cabin fit')
           where s.world_id = dw and s.kind = 'cabin' and s.note ~ '^\S+ first cabin fit'
             and s.spent_on >= (select (x.value #>> '{}')::date from public.settings x where x.world_id = dw and x.airline_id is null and x.key = 'cabin_charge_check_from')
             and p.paid_at >= (select (x.value #>> '{}')::date from public.settings x where x.world_id = dw and x.airline_id is null and x.key = 'cabin_charge_check_from')::timestamp at time zone 'UTC') g;
  raise notice 'on the copy, timing: %', v_gap;
end
$test$;

-- ---------------------------------------------------------------- 3. a world of its own
do $setup$
declare dw bigint := (select id from public.worlds where is_default); w bigint; g bigint; gr bigint; al bigint; rv bigint; ac record;
  t timestamptz; a jsonb := '{}'::jsonb;
begin
  perform set_config('equinox.actor', 'claude', true), set_config('equinox.actor_detail', 'cabin charges test', true);
  insert into public.worlds (name, game_host, kind) values ('cabin charges test', 'cabin-charges.test', 'exclusive') returning id into w;
  insert into public.settings (world_id, airline_id, key, value, unit, description)
  select w, null, s.key, s.value, s.unit, s.description from public.settings s where s.world_id = dw and s.airline_id is null;
  update public.settings set value = '"2099-03-01"'::jsonb where world_id = w and airline_id is null and key = 'cabin_charge_check_from';
  insert into public.groups (world_id, name, kind) values (w, 'ours', 'ours') returning id into g;
  insert into public.groups (world_id, name, kind) values (w, 'rivals', 'rival') returning id into gr;
  insert into public.airlines (world_id, group_id, game_id, planner_name, public_name, iata_code, active, position)
  values (w, g, 990801, 'Cabin Test', 'Cabin Test', 'CQ', true, 1) returning id into al;
  -- a rival's installation line is no business of ours
  insert into public.airlines (world_id, group_id, game_id, game_name, active) values (w, gr, 990802, 'Cabin Rival', true) returning id into rv;
  for ac in select 'CQ-00' || n as reg from generate_series(1, 8) n loop
    insert into public.aircraft (world_id, airline_id, registration, status) values (w, al, ac.reg, 'active') returning id into g;
    a := a || jsonb_build_object(ac.reg, g);
  end loop;
  -- the first fits as Tails' filing logs them, a refit row (kind cabin, not a first fit), and a fit before the setting's day
  insert into public.spending_log (world_id, airline_id, spent_on, amount, kind, aircraft_id, note) values
    (w, al, date '2099-03-02', 97000, 'cabin', (a ->> 'CQ-001')::bigint, 'CQ-001 first cabin fit (E195-LEI)'),
    (w, al, date '2099-03-02', 97000, 'cabin', (a ->> 'CQ-002')::bigint, 'CQ-002 first cabin fit (E195-LEI)'),
    (w, al, date '2099-03-02', 97000, 'cabin', (a ->> 'CQ-003')::bigint, 'CQ-003 first cabin fit (E195-LEI)'),
    (w, al, date '2099-03-02', 97000, 'cabin', (a ->> 'CQ-004')::bigint, 'CQ-004 first cabin fit (E195-LEI)'),
    (w, al, date '2099-03-05', 97000, 'cabin', (a ->> 'CQ-005')::bigint, 'CQ-005 first cabin fit (E195-LEI)'),
    (w, al, date '2099-02-27', 97000, 'cabin', (a ->> 'CQ-007')::bigint, 'CQ-007 first cabin fit (E195-LEI)'),
    (w, al, date '2099-03-03', 5000, 'cabin', (a ->> 'CQ-002')::bigint, 'refit CQ-002: E195-LEI OLD → new E195-LEI (test)');
  -- the bank statement, each installation with the pilot training an order brings beside it, folded as the capture folds
  -- it: CQ-001 at the logged amount, CQ-002 at another, CQ-003 twice, CQ-006 with no fit, CQ-007 after the day though its
  -- fit was before, CQ-008 before the day; and the latest line, 6 Mar 12:00
  insert into public.game_statement (world_id, airline_id, airline, ts, descr, amount, side, occ, blk) values
    (w, al, 'Cabin Test', '2099-03-01 22:00+00', 'Installation of cabin interior (CQ-001)', 97000, 'D', 1, 1),
    (w, al, 'Cabin Test', '2099-03-01 22:00+00', 'Pilot training', 156800, 'D', 1, 1),
    (w, al, 'Cabin Test', '2099-03-02 03:00+00', 'Installation of cabin interior (CQ-002)', 99000, 'D', 1, 1),
    (w, al, 'Cabin Test', '2099-03-02 03:00+00', 'Pilot training', 156800, 'D', 1, 1),
    (w, al, 'Cabin Test', '2099-03-02 04:00+00', 'Installation of cabin interior (CQ-003)', 97000, 'D', 1, 1),
    (w, al, 'Cabin Test', '2099-03-03 04:00+00', 'Installation of cabin interior (CQ-003)', 97000, 'D', 1, 1),
    (w, al, 'Cabin Test', '2099-03-03 05:00+00', 'Installation of cabin interior (CQ-006)', 88000, 'D', 1, 1),
    (w, al, 'Cabin Test', '2099-03-03 05:00+00', 'Pilot training', 156800, 'D', 1, 1),
    (w, al, 'Cabin Test', '2099-03-02 06:00+00', 'Installation of cabin interior (CQ-007)', 97000, 'D', 1, 1),
    (w, al, 'Cabin Test', '2099-02-28 06:00+00', 'Installation of cabin interior (CQ-008)', 88000, 'D', 1, 1),
    (w, al, 'Cabin Test', '2099-03-06 12:00+00', 'Leasing rate for CQ-001', 50000, 'D', 1, 1);
  perform private.fold_statement(al, array(select distinct s.ts from public.game_statement s where s.airline_id = al));
  insert into public.game_statement (world_id, airline_id, airline, ts, descr, amount, side, occ, blk) values
    (w, rv, 'Cabin Rival', '2099-03-02 07:00+00', 'Installation of cabin interior (CQ-009)', 50000, 'D', 1, 1);
  perform private.fold_statement(rv, array[timestamptz '2099-03-02 07:00+00']);
  perform set_config('equinox.actor', '', true), set_config('equinox.actor_detail', '', true);
  insert into t_cc values ('w', to_jsonb(w)), ('al', to_jsonb(al)), ('aircraft', a), ('mark', to_jsonb(coalesce((select max(id) from public.change_log), 0)));
end
$setup$;

do $test$
declare w bigint := (select (v #>> '{}')::bigint from t_cc where k = 'w'); al bigint := (select (v #>> '{}')::bigint from t_cc where k = 'al');
  a jsonb := (select v from t_cc where k = 'aircraft'); d jsonb; got text; p jsonb;
begin
  -- the fold: each installation line its registration and aircraft; pilot training and the lease neither aircraft
  select string_agg(coalesce(p.registration, '-') || ' ' || coalesce((p.aircraft_id = (a ->> p.registration)::bigint)::text, '-') || ' ' || p.kind,
                    ', ' order by p.paid_at, p.descr) into got
    from public.game_payments p where p.airline_id = al;
  assert got = 'CQ-008 true cabin, CQ-001 true cabin, - - cabin, CQ-002 true cabin, - - cabin, CQ-003 true cabin, CQ-007 true cabin, CQ-003 true cabin, CQ-006 true cabin, - - cabin, CQ-001 - lease',
    'the folded payments (registration, its aircraft, kind) are ' || coalesce(got, 'none');

  d := private.fig_cabin_charges(w, now());
  insert into t_cc values ('doc', d);
  assert d ->> 'check_from' = '2099-03-01' and (d ->> 'wait_days')::int = 2, 'the check isn''t from 2099-03-01 with 2 days to wait: ' || (d - 'problems')::text;
  assert d -> 'counts' = '{"checked": 5, "matches": 1, "differs": 1, "charged_twice": 1, "not_charged": 1, "waiting": 1, "not_logged": 1, "problems": 4}'::jsonb,
    'the counts aren''t 5 checked, one of each state, 4 problems: ' || (d -> 'counts')::text;
  select string_agg(x ->> 'state' || ' ' || (x ->> 'registration') || ' ' || jsonb_array_length(x -> 'lines'), ', ' order by i) into got
    from jsonb_array_elements(d -> 'problems') with ordinality e(x, i);
  assert got = 'differs CQ-002 1, charged_twice CQ-003 2, not_charged CQ-004 0, not_logged CQ-006 1',
    'the problems, in order, are ' || coalesce(got, 'none');
  p := d -> 'problems' -> 0;
  assert (p ->> 'game_amount')::numeric = 99000 and (p ->> 'difference')::numeric = 2000 and (p #>> '{logged,amount}')::numeric = 97000
     and p #>> '{logged,config}' = 'E195-LEI' and p #>> '{logged,spent_on}' = '2099-03-02' and p ->> 'code' = 'CQ' and p ->> 'airline' = 'Cabin Test'
     and (p ->> 'aircraft_id')::bigint = (a ->> 'CQ-002')::bigint and p #> '{logged,updated_at}' is not null
     and p #>> '{lines,0,descr}' = 'Installation of cabin interior (CQ-002)',
    'CQ-002 doesn''t differ by 2,000 (97,000 logged, 99,000 charged) with its airline, aircraft, config and line: ' || p::text;
  p := d -> 'problems' -> 3;
  assert p -> 'logged' = 'null'::jsonb and (p ->> 'aircraft_id')::bigint = (a ->> 'CQ-006')::bigint and (p #>> '{lines,0,amount}')::numeric = 88000,
    'CQ-006 isn''t "not logged" with its aircraft and its line: ' || p::text;
  -- the setting's day: CQ-007 (fit before it) isn't checked nor "not logged"; CQ-008 (line before it) isn't listed; the
  -- rival's line isn't ours; pilot training is no charge anywhere
  assert (d -> 'problems')::text not like '%CQ-007%' and (d -> 'problems')::text not like '%CQ-008%' and (d -> 'problems')::text not like '%CQ-009%'
     and (d -> 'problems')::text not like '%Pilot training%',
    'a fit or line before the setting''s day, a rival''s line or pilot training shows up: ' || (d -> 'problems')::text;
  -- waiting turns to not charged once the latest statement line is more than 2 days after it was logged
  insert into public.game_statement (world_id, airline_id, airline, ts, descr, amount, side, occ, blk)
  values (w, al, 'Cabin Test', '2099-03-07 01:00+00', 'Leasing rate for CQ-002', 50000, 'D', 1, 1);
  d := private.fig_cabin_charges(w, now());
  assert (d #>> '{counts,waiting}')::int = 0 and (d #>> '{counts,not_charged}')::int = 2, 'CQ-005 didn''t turn "not charged yet" after 2 days: ' || (d -> 'counts')::text;
  -- and back: only what was recorded by the moment counts (the moment before this test made anything: nothing)
  d := private.fig_cabin_charges(w, now() - interval '1 second');
  assert (d #>> '{counts,checked}')::int = 0 and jsonb_array_length(d -> 'problems') = 0, 'rows recorded after the moment were read: ' || (d -> 'counts')::text;
  delete from public.game_statement where airline_id = al and ts = '2099-03-07 01:00+00';
  -- no setting: nothing checked
  update public.settings set value = 'null'::jsonb where world_id = w and airline_id is null and key = 'cabin_charge_check_from';
  d := private.fig_cabin_charges(w, now());
  assert (d #>> '{counts,checked}')::int = 0 and (d #>> '{counts,not_logged}')::int = 0 and d -> 'check_from' = 'null'::jsonb,
    'with no setting something was checked: ' || (d - 'problems')::text;
  update public.settings set value = '"2099-03-01"'::jsonb where world_id = w and airline_id is null and key = 'cabin_charge_check_from';
  raise notice 'hand-made: the fold names each installation''s registration and aircraft, pilot training neither; one fit of each state (CQ-001 matches, CQ-002 differs by 2,000, CQ-003 charged twice, CQ-004 not charged yet, CQ-005 waiting, then not charged after 2 days; CQ-006 not logged); a fit and a line before the setting''s day, a rival''s line and pilot training left out; nothing without the setting';
end
$test$;

-- ---------------------------------------------------------------- 4. Use the game's amount, as staff; who is refused
do $$ begin perform set_config('request.jwt.claims',
  '{"sub": "00000000-0000-4000-8000-0000000000d1", "email": "cabin-charges-staff@example.com", "role": "authenticated"}', true); end $$;
set local role authenticated;
do $test$
declare d jsonb := (select v from t_cc where k = 'doc'); p jsonb; r jsonb;
begin
  -- the differing fit, as Systems → Cabin charges' Use the game's amount saves it
  select x into p from jsonb_array_elements(d -> 'problems') x where x ->> 'state' = 'differs';
  r := public.planner_save(jsonb_build_array(jsonb_build_object('table', 'spending_log', 'op', 'update', 'key', jsonb_build_object('id', (p #>> '{logged,id}')::bigint),
         'base', p #> '{logged,updated_at}', 'values', jsonb_build_object('amount', (p ->> 'game_amount')::numeric))), 'cabin-charges-test');
  assert (r ->> 'ok')::boolean, 'planner_save() didn''t take the game''s amount from the figure''s updated_at: ' || r::text;
  -- staff get what postgres gets (the default world, at a fixed moment)
  insert into t_cc values ('staff', public.cabin_charges(timestamptz '2026-10-22 12:00+00'));
end
$test$;
reset role;

do $test$
declare w bigint := (select (v #>> '{}')::bigint from t_cc where k = 'w'); mark bigint := (select (v #>> '{}')::bigint from t_cc where k = 'mark');
  d jsonb; got text;
begin
  d := private.fig_cabin_charges(w, now());
  assert (d #>> '{counts,matches}')::int = 2 and (d #>> '{counts,differs}')::int = 0, 'after Use the game''s amount CQ-002 doesn''t match: ' || (d -> 'counts')::text;
  select string_agg(c.table_name || ' ' || c.op || ' ' || c.actor || ' ' || c.actor_detail, ', ') into got
    from public.change_log c where c.id > mark and c.table_name = 'spending_log' and c.actor = 'planner';
  assert got = 'spending_log update planner cabin-charges-test', 'the save wasn''t one spending_log update logged as planner with the tab: ' || coalesce(got, 'nothing');
  assert (select v from t_cc where k = 'staff') = private.fig_cabin_charges((select id from public.worlds where is_default), timestamptz '2026-10-22 12:00+00'),
    'staff don''t get what postgres gets from cabin_charges()';
end
$test$;

set local role anon;
do $test$
declare n int := 0;
begin
  begin perform public.cabin_charges(); exception when insufficient_privilege then n := n + 1; end;
  assert n = 1, 'signed out, cabin_charges() wasn''t refused';
end
$test$;
reset role;

do $$ begin perform set_config('request.jwt.claims',
  '{"sub": "00000000-0000-4000-8000-0000000000d2", "email": "cabin-charges-other@example.com", "role": "authenticated"}', true); end $$;
set local role authenticated;
do $test$
declare n int := 0;
begin
  begin perform public.cabin_charges(); exception when insufficient_privilege then n := n + 1; end;
  assert n = 1, 'an account that isn''t staff wasn''t refused cabin_charges()';
end
$test$;
reset role;

do $$ begin raise notice 'Use the game''s amount: one spending_log update through planner_save() as staff, logged as planner, and the fit matches; signed out and an account that isn''t staff refused; staff get what postgres gets'; end $$;
do $$ begin raise notice 'cabin charges: all checks passed'; end $$;

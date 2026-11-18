-- The salary table (migration 20261116100000; spec docs/specs/2026-11-16-salary-table.md; manual §7). Run by
-- database/rehearse.sh on the copy of last night's backup, after the new migrations, inside a transaction that is rolled
-- back. A failed check stops with an error that says which (names, kinds and counts, never a key).
--   1. airlines.game_country_id, described, set for our six airlines in Gander by their game ids (USA 182, India 61,
--      Ireland 65, United Kingdom 54, China 30, Malaysia 97); the two settings (salary_flag_pct 1 per cent,
--      unattended_salary_read true), world rows in every world, described, with since and reason.
--   2. The four tables: RLS on, no rule, no access for anon or staff, every table and column described;
--      salary_positions holds Kingfisher's three pilot families.
--   3. capture_airlines(): each airline's country_id; salary_read true for a normal key; for the unattended key true with
--      unattended_salary_read and false without, while its salary_above_average_pct stays null (it never sets one).
--   4. capture_ingest() kind salaries, signed out as the capture calls it: stored (raw page, read, positions, averages);
--      the mapping (A320 family → Narrow-body pilots); the flag just under and just over 1% both ways and at exactly 1%;
--      a position with no staff never flagged; an unmapped family and a position missing from the country page shown as
--      no_average and the read short; a country page that didn't read short; an Employee overview that didn't read
--      broken. None of them changes the airline's verdict or the day's completeness.
--   5. The unattended key: its page stored as unattended; refused while unattended_salary_read is false.
--   6. salary_table(): staff only (anon refused), the stored kind in the planner_figures list (figures_refresh() names
--      it), and its answer as the test expects.

create temporary table t_st (k text primary key, v jsonb) on commit drop;
grant select, insert on t_st to anon;

-- ---------------------------------------------------------------- 1. the column and the settings
do $test$
declare bad text;
begin
  assert coalesce(col_description('public.airlines'::regclass,
                                  (select attnum from pg_attribute where attrelid = 'public.airlines'::regclass and attname = 'game_country_id')), '') like '%country%',
    'airlines.game_country_id is missing or not described';
  select string_agg(a.game_id || ' ' || coalesce(a.game_country_id::text, 'null'), ', ') into bad
    from public.airlines a join public.worlds w on w.id = a.world_id and w.game_host = 'gander.airlinesim.aero'
    join (values (114, 182), (113, 61), (112, 65), (203, 54), (208, 30), (210, 97)) x(game_id, country_id) on x.game_id = a.game_id
   where a.game_country_id is distinct from x.country_id;
  assert bad is null, 'our airlines'' country ids in Gander aren''t as the migration set them: ' || bad;
  assert not exists (select 1 from public.worlds w cross join (values ('salary_flag_pct'), ('unattended_salary_read')) k(key)
                      where not exists (select 1 from public.settings s where s.world_id = w.id and s.airline_id is null and s.key = k.key
                                           and length(coalesce(s.description, '')) > 100 and s.since is not null and coalesce(s.reason, '') <> '')),
    'a world lacks a described salary_flag_pct or unattended_salary_read with since and reason';
  assert (select s.value = '1'::jsonb and s.unit = 'percent' from public.settings s
           where s.world_id = (select id from public.worlds where is_default) and s.airline_id is null and s.key = 'salary_flag_pct'),
    'the default world''s salary_flag_pct isn''t 1 percent';
  assert (select s.value = 'true'::jsonb from public.settings s
           where s.world_id = (select id from public.worlds where is_default) and s.airline_id is null and s.key = 'unattended_salary_read'),
    'the default world''s unattended_salary_read isn''t true';
  assert (select s.value = 'false'::jsonb from public.settings s
           where s.world_id = (select id from public.worlds where is_default) and s.airline_id is null and s.key = 'unattended_salaries'),
    'unattended_salaries changed: the unattended capture must still never set a salary';
  raise notice 'airlines.game_country_id set for our six in Gander; salary_flag_pct 1 percent and unattended_salary_read true, described, in every world; unattended_salaries still false';
end
$test$;

-- ---------------------------------------------------------------- 2. the tables
do $test$
declare t text; bad text;
begin
  foreach t in array array['salary_reads', 'airline_salaries', 'country_salaries', 'salary_positions'] loop
    assert (select c.relrowsecurity from pg_class c where c.oid = ('public.' || t)::regclass), t || ' has no row level security';
    assert not exists (select 1 from pg_policies p where p.schemaname = 'public' and p.tablename = t), t || ' has a rule';
    assert not has_table_privilege('anon', 'public.' || t, 'select, insert, update, delete')
       and not has_table_privilege('authenticated', 'public.' || t, 'select, insert, update, delete'), t || ' can be reached by anon or staff';
    assert length(coalesce(obj_description(('public.' || t)::regclass, 'pg_class'), '')) > 100, t || ' isn''t described';
    select string_agg(a.attname, ', ') into bad from pg_attribute a
     where a.attrelid = ('public.' || t)::regclass and a.attnum > 0 and not a.attisdropped
       and a.attname not in ('id', 'world_id', 'airline_id', 'read_id', 'created_at')
       and coalesce(col_description(a.attrelid, a.attnum), '') = '';
    assert bad is null, t || ' has columns without a description: ' || bad;
  end loop;
  assert (select count(*) from public.salary_positions m where m.world_id = (select id from public.worlds where is_default)
           and (m.overview_name, m.country_name) in (('EMB-170 / -175 / -190 / -195', 'Regional Jet pilots'),
                                                     ('A318 / A319 / A320 / A321', 'Narrow-body pilots'),
                                                     ('A330 / A340 / A350', 'Wide-body Pilots'))) = 3,
    'salary_positions lacks Kingfisher''s three pilot families';
  raise notice 'the four tables: RLS on, no rule, no access for anon or staff, described; salary_positions seeded with the three pilot families';
end
$test$;

-- ---------------------------------------------------------------- 3. capture_airlines()
create or replace function pg_temp.st_set(p_key text, p_value jsonb) returns void language sql as $$
  update public.settings s set value = p_value
   where s.world_id = (select id from public.worlds where is_default) and s.airline_id is null and s.key = p_key
$$;
do $setup$
begin
  insert into public.capture_keys (label, key_hash, world_id, unattended)
  select 'salary table test, normal', extensions.crypt('salary-table-test-normal', extensions.gen_salt('bf')), w.id, false
    from public.worlds w where w.is_default;
  insert into public.capture_keys (label, key_hash, world_id, unattended)
  select 'salary table test, unattended', extensions.crypt('salary-table-test-unattended', extensions.gen_salt('bf')), w.id, true
    from public.worlds w where w.is_default;
  -- the airlines' verdicts and the day's completeness before any salaries page (they must not move)
  insert into t_st
  select 'verdict_before', jsonb_object_agg(a.id, private.capture_airline_verdict(a.id, now()))
    from public.airlines a join public.groups g on g.id = a.group_id and g.world_id = a.world_id
   where a.world_id = (select id from public.worlds where is_default) and a.active and g.kind = 'ours';
  insert into t_st values ('complete_before', to_jsonb(private.capture_day_complete((select id from public.worlds where is_default),
                                                                                    private.capture_day((select id from public.worlds where is_default), now()))));
end
$setup$;

set local role anon;
do $test$
begin
  insert into t_st values ('a_n', public.capture_airlines('salary-table-test-normal')),
                          ('a_un', public.capture_airlines('salary-table-test-unattended'));
end
$test$;
reset role;
select pg_temp.st_set('unattended_salary_read', 'false'::jsonb);
set local role anon;
do $test$
begin
  insert into t_st values ('b_un', public.capture_airlines('salary-table-test-unattended'));
end
$test$;
reset role;
select pg_temp.st_set('unattended_salary_read', 'true'::jsonb);

do $test$
declare an jsonb := (select v from t_st where k = 'a_n'); au jsonb := (select v from t_st where k = 'a_un'); bu jsonb := (select v from t_st where k = 'b_un');
  bad text;
begin
  assert an ->> 'ok' = 'true' and au ->> 'ok' = 'true', 'capture_airlines() refused a test key';
  select string_agg(e ->> 'game_id', ', ') into bad from jsonb_array_elements(an -> 'airlines') e
   where not e ? 'country_id'
      or e -> 'country_id' is distinct from (select to_jsonb(a.game_country_id) from public.airlines a
                                              where a.world_id = (select id from public.worlds where is_default) and a.game_id = (e ->> 'game_id')::int);
  assert bad is null, 'capture_airlines() doesn''t give these airlines'' country_id: ' || bad;
  assert an -> 'salary_read' = 'true'::jsonb, 'a normal key isn''t told to read salaries';
  assert au -> 'salary_read' = 'true'::jsonb, 'the unattended key isn''t told to read salaries with unattended_salary_read true';
  assert au -> 'salary_above_average_pct' = 'null'::jsonb, 'the unattended key is given the salary setting: it must never set a salary';
  assert bu -> 'salary_read' = 'false'::jsonb and bu -> 'salary_above_average_pct' = 'null'::jsonb,
    'with unattended_salary_read false the unattended key is still told to read salaries, or given the salary setting';
  raise notice 'capture_airlines(): each airline''s country_id; salary_read true for a press, the setting''s for the unattended key, which never gets salary_above_average_pct';
end
$test$;

-- ---------------------------------------------------------------- 4. pages, signed out as the capture sends them
-- Kingfisher (113): averages 1,000 → target 1,050 (1% = 10.5): 1,060 and 1,040 within (0.95%), 1,061 over and 1,039 under
-- (1.05%); 2,000 → 2,100: 2,121 exactly 1%, within. Logistics 5,000 with no staff; a B737 family unmapped; the A320 family
-- through salary_positions; Fleet management's own page average 990 against the country's 1,000 (averages differ).
set local role anon;
do $test$
declare ov jsonb; co jsonb;
begin
  ov := jsonb_build_array(
    jsonb_build_object('position', 'A318 / A319 / A320 / A321', 'group', 'Flight crew', 'employed', 10, 'active', 10, 'required', 10, 'salary', '1,000 AS$', 'salary_next', 1060, 'avg', 1000),
    jsonb_build_object('position', 'B737 / B738', 'group', 'Flight crew', 'employed', 5, 'salary', 900, 'salary_next', 900, 'avg', 880),
    jsonb_build_object('position', 'Pursers', 'group', 'Cabin crew', 'employed', 3, 'salary', 1000, 'salary_next', 1061, 'avg', 1000, 'raised_to', 1061),
    jsonb_build_object('position', 'Check-in agents', 'group', 'Ground crew', 'employed', 3, 'salary', 1000, 'salary_next', 1040, 'avg', 1000),
    jsonb_build_object('position', 'Ramp agents', 'group', 'Ground crew', 'employed', 3, 'salary', 1000, 'salary_next', 1039, 'avg', 1000),
    jsonb_build_object('position', 'Administration', 'group', 'Ground crew', 'employed', 3, 'salary', 2000, 'salary_next', 2121, 'avg', 2000),
    jsonb_build_object('position', 'Fleet management', 'group', 'Ground crew', 'employed', 3, 'salary', 1050, 'salary_next', 1050, 'avg', 990),
    jsonb_build_object('position', 'Logistics', 'group', 'Ground crew', 'employed', 0, 'salary', 5000, 'salary_next', 5000, 'avg', 720));
  co := jsonb_build_object('id', 61, 'name', 'India', 'code', 'IN', 'averages', jsonb_build_array(
    jsonb_build_object('position', 'Narrow-body pilots', 'avg', 1000), jsonb_build_object('position', 'Pursers', 'avg', 1000),
    jsonb_build_object('position', 'Check-in agents', 'avg', 1000), jsonb_build_object('position', 'Ramp agents', 'avg', 1000),
    jsonb_build_object('position', 'Administration', 'avg', 2000), jsonb_build_object('position', 'Fleet management', 'avg', 1000),
    jsonb_build_object('position', 'Logistics', 'avg', 720)));
  insert into t_st values ('kf', public.capture_ingest('salary-table-test-normal', '113', 'salaries', 'https://gander.airlinesim.aero/app/enterprise/staffOverview',
                                                       jsonb_build_object('version', '1.18', 'overview', jsonb_build_object('rows', ov), 'country', co)));
  -- Malaysia (210): its country page has no wide-body row, and it has wide-body pilots
  insert into t_st values ('mh', public.capture_ingest('salary-table-test-normal', '210', 'salaries', 'https://gander.airlinesim.aero/app/enterprise/staffOverview',
    jsonb_build_object('overview', jsonb_build_object('rows', jsonb_build_array(
        jsonb_build_object('position', 'A330 / A340 / A350', 'employed', 4, 'salary_next', 1700, 'avg', 1600),
        jsonb_build_object('position', 'Pursers', 'employed', 4, 'salary_next', 554, 'avg', 528))),
      'country', jsonb_build_object('id', 97, 'name', 'Malaysia', 'code', 'MY', 'averages', jsonb_build_array(
        jsonb_build_object('position', 'Narrow-body pilots', 'avg', 1508), jsonb_build_object('position', 'Pursers', 'avg', 528))))));
  -- Virgin (203): the country page didn't read
  insert into t_st values ('vs', public.capture_ingest('salary-table-test-normal', '203', 'salaries', 'p',
    jsonb_build_object('overview', jsonb_build_object('rows', jsonb_build_array(jsonb_build_object('position', 'Pursers', 'employed', 2, 'salary_next', 523, 'avg', 498))),
                       'country', jsonb_build_object('id', 54, 'error', 'HTTP 503'))));
  -- China Eastern (208): the Employee overview didn't read
  insert into t_st values ('mu', public.capture_ingest('salary-table-test-normal', '208', 'salaries', 'p',
    jsonb_build_object('overview', jsonb_build_object('error', 'not the Employee overview page'), 'country', jsonb_build_object('id', 30, 'averages', '[]'::jsonb))));
  -- Pan Am (114) by the unattended key: stored, marked unattended
  insert into t_st values ('pa_un', public.capture_ingest('salary-table-test-unattended', '114', 'salaries', 'p',
    jsonb_build_object('overview', jsonb_build_object('rows', jsonb_build_array(jsonb_build_object('position', 'Pursers', 'employed', 2, 'salary_next', 536, 'avg', 510))),
                       'country', jsonb_build_object('id', 182, 'name', 'USA', 'code', 'US', 'averages', jsonb_build_array(jsonb_build_object('position', 'Pursers', 'avg', 510))))));
  insert into t_st values ('bad_kind', public.capture_ingest('salary-table-test-normal', '114', 'salary', 'p', '{}'::jsonb));
end
$test$;
reset role;
select pg_temp.st_set('unattended_salary_read', 'false'::jsonb);
set local role anon;
do $test$
begin
  insert into t_st values ('pa_un_off', public.capture_ingest('salary-table-test-unattended', '114', 'salaries', 'p',
    jsonb_build_object('overview', jsonb_build_object('rows', '[]'::jsonb))));
end
$test$;
reset role;
select pg_temp.st_set('unattended_salary_read', 'true'::jsonb);

do $test$
declare kf jsonb := (select v from t_st where k = 'kf'); mh jsonb := (select v from t_st where k = 'mh');
  vs jsonb := (select v from t_st where k = 'vs'); mu jsonb := (select v from t_st where k = 'mu');
  pu jsonb := (select v from t_st where k = 'pa_un'); off jsonb := (select v from t_st where k = 'pa_un_off');
  w bigint := (select id from public.worlds where is_default); t jsonb; al jsonb; r jsonb; v_after jsonb; bad text;
begin
  assert kf ->> 'ok' = 'true' and kf ->> 'kind' = 'salaries' and (kf ->> 'rows')::int = 8, 'Kingfisher''s salaries page wasn''t stored with its 8 positions: ' || kf::text;
  assert kf #>> '{verdict,verdict}' = 'short' and kf ->> 'words' like '%no country average for B737 / B738%',
    'an unmapped pilot family with staff doesn''t make the read short, named: ' || coalesce(kf ->> 'words', '');
  assert (kf ->> 'off_target')::int = 2, 'Kingfisher''s reply counts ' || (kf ->> 'off_target') || ' positions off target, not 2 (Pursers over, Ramp agents under)';
  assert (select x.kind = 'salaries' and x.verdict = 'short' and x.verdict_note = kf ->> 'words' from public.game_capture_raw x
           where x.id = (select r.raw_id from public.salary_reads r where r.id = (kf ->> 'read_id')::bigint)),
    'the raw page doesn''t keep the salaries page and its verdict';
  assert (select count(*) from public.country_salaries c where c.read_id = (kf ->> 'read_id')::bigint) = 7, 'the country page''s 7 averages weren''t stored';
  assert (select r.country_id = 61 and r.country_code = 'IN' and r.version = '1.18' and not r.unattended from public.salary_reads r where r.id = (kf ->> 'read_id')::bigint),
    'the read''s country, version or key isn''t as sent';
  assert (select s.salary = 1000 and s.raised_to is null from public.airline_salaries s where s.read_id = (kf ->> 'read_id')::bigint and s.n = 0),
    'a salary sent as "1,000 AS$" wasn''t stored as 1000';
  assert mh #>> '{verdict,verdict}' = 'short' and mh ->> 'words' like '%no country average for A330 / A340 / A350%',
    'a position missing from the country page doesn''t make the read short, named: ' || coalesce(mh ->> 'words', '');
  assert vs #>> '{verdict,verdict}' = 'short' and vs ->> 'words' like '%the country page didn''t read (HTTP 503)%',
    'a country page that didn''t read isn''t short with its reason: ' || coalesce(vs ->> 'words', '');
  assert mu #>> '{verdict,verdict}' = 'broken' and mu ->> 'words' like '%Employee overview page didn''t read%',
    'an Employee overview that didn''t read isn''t broken: ' || coalesce(mu ->> 'words', '');
  assert pu ->> 'ok' = 'true' and pu #>> '{verdict,verdict}' = 'ok'
     and (select r.unattended from public.salary_reads r where r.id = (pu ->> 'read_id')::bigint), 'the unattended key''s page wasn''t stored as unattended and ok';
  assert off ->> 'ok' = 'false' and off ->> 'error' like '%unattended_salary_read%', 'the unattended key''s page wasn''t refused with unattended_salary_read false';
  assert (select v from t_st where k = 'bad_kind') = '{"ok": false, "error": "bad kind"}'::jsonb, 'an unknown kind isn''t refused as before';

  -- the verdicts and the day's completeness didn't move
  select jsonb_object_agg(a.id, private.capture_airline_verdict(a.id, now())) into v_after
    from public.airlines a join public.groups g on g.id = a.group_id and g.world_id = a.world_id
   where a.world_id = w and a.active and g.kind = 'ours';
  assert v_after = (select v from t_st where k = 'verdict_before'), 'a salaries page changed an airline''s verdict';
  assert to_jsonb(private.capture_day_complete(w, private.capture_day(w, now()))) = (select v from t_st where k = 'complete_before'),
    'a salaries page changed the day''s completeness';

  -- 6. the table
  t := private.fig_salary_table(w, now());
  assert t -> 'flag_pct' = '1'::jsonb and t -> 'above_pct' = '5'::jsonb, 'the table''s settings aren''t 1 and 5: ' || left(t::text, 200);
  select e into al from jsonb_array_elements(t -> 'airlines') e where (e ->> 'code') = (select a.iata_code from public.airlines a where a.world_id = w and a.game_id = 113);
  assert al is not null and al ->> 'verdict' = 'short' and al #>> '{country,code}' = 'IN', 'Kingfisher isn''t in the table with its read';
  select string_agg(format('%s %s %s', x ->> 'position', coalesce(x ->> 'flag', '-'), coalesce(x ->> 'target', '-')), '; ' order by o) into bad
    from jsonb_array_elements(al -> 'rows') with ordinality y(x, o);
  assert bad = 'A318 / A319 / A320 / A321 - 1050; B737 / B738 no_average -; Pursers over 1050; Check-in agents - 1050; Ramp agents under 1050; Administration - 2100; Fleet management - 1050; Logistics - 756',
    'the rows'' flags and targets aren''t as expected: ' || bad;
  select x into r from jsonb_array_elements(al -> 'rows') x where x ->> 'position' = 'Pursers';
  assert (r ->> 'diff')::int = 11 and (r ->> 'diff_pct')::numeric = 1.05 and (r ->> 'raised_to')::int = 1061 and (r ->> 'salary')::int = 1000,
    'Pursers'' difference, per cent, raise or this week''s salary isn''t as sent: ' || r::text;
  select x into r from jsonb_array_elements(al -> 'rows') x where x ->> 'position' = 'Fleet management';
  assert (r ->> 'averages_differ')::boolean and (r ->> 'overview_avg')::int = 990 and (r ->> 'country_avg')::int = 1000, 'two averages 1% apart aren''t marked';
  select x into r from jsonb_array_elements(al -> 'rows') x where x ->> 'position' = 'Logistics';
  assert r -> 'flag' = 'null'::jsonb and (r ->> 'employed')::int = 0, 'a position with no staff is flagged';
  assert (al #>> '{counts,flagged}')::int = 2 and (al #>> '{counts,under}')::int = 1 and (al #>> '{counts,over}')::int = 1
     and (al #>> '{counts,no_average}')::int = 1, 'Kingfisher''s counts aren''t 2 flagged, 1 under, 1 over, 1 no average: ' || (al -> 'counts')::text;
  select e into al from jsonb_array_elements(t -> 'airlines') e where (e ->> 'code') = (select a.iata_code from public.airlines a where a.world_id = w and a.game_id = 208);
  assert al ->> 'verdict' = 'broken' and jsonb_array_length(al -> 'rows') = 0, 'China Eastern''s broken read isn''t shown with no rows';
  select e into al from jsonb_array_elements(t -> 'airlines') e where (e ->> 'code') = (select a.iata_code from public.airlines a where a.world_id = w and a.game_id = 203);
  assert (select x ->> 'flag' from jsonb_array_elements(al -> 'rows') x where x ->> 'position' = 'Pursers') = 'no_average',
    'a position with staff and no country page isn''t no_average';
  assert (t #>> '{counts,flagged}')::int >= 2 and (t #>> '{counts,airlines_flagged}')::int >= 1, 'the table''s counts miss Kingfisher''s flags';
  -- an earlier moment sees none of it
  assert not exists (select 1 from jsonb_array_elements(private.fig_salary_table(w, now() - interval '1 second') -> 'airlines') e
                      where e ->> 'read_at' >= private.fig_ts(now())),
    'a moment before the reads sees them';

  -- staff only, and stored with the figures
  assert not has_function_privilege('anon', 'public.salary_table(bigint, timestamptz)', 'execute')
     and has_function_privilege('authenticated', 'public.salary_table(bigint, timestamptz)', 'execute'), 'salary_table() isn''t staff only';
  assert position('''salary_table''' in pg_get_functiondef('private.figures_refresh(bigint, timestamptz, text)'::regprocedure)) > 0,
    'private.figures_refresh() doesn''t store salary_table';
  raise notice 'capture_ingest() kind salaries: stored and judged (ok, short for an unmapped family, a missing country row or a failed country page, broken for a failed overview), never moving a verdict or the day''s completeness; the unattended key''s read marked and refused when switched off; salary_table() flags 1.05%% both ways and not 0.95%% or exactly 1%%, no staff never, two averages apart marked; staff only; stored by figures_refresh()';
end
$test$;

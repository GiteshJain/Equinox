-- The unattended capture, part 1 (spec docs/specs/2026-11-10-unattended-capture.md §1 and §5; migration
-- 20261110040000). Run by database/rehearse.sh on the copy of last night's backup, after the new migrations, inside a
-- transaction that is rolled back. A failed check stops with an error that says which (names, counts and words, never
-- keys).
--   1. The catalogue: capture_keys.unattended (boolean, not null, default false, described; every key the copy has is
--      false); job_runs takes capture_unattended and capture_dispatch; the four settings in every world, described, with
--      their values; the new functions are postgres's only (not anon, authenticated, service_role or public), run as
--      the caller with an empty search path, and described; pg_net is switched on.
--   2. private.capture_key_issue() makes a 64-character key that private.capture_key_world() accepts, keeps only its
--      hash, and marks it unattended or not as asked; private.capture_key_unattended() says so (false for a wrong key); a
--      world that doesn't exist or no label is refused.
--   3. capture_airlines(), signed out as the capture calls it: with the unattended key it follows each of the three
--      settings (no salaries while unattended_salaries is false; the scan and the market pages exactly as for a normal
--      key while their settings are true, and not due when switched off; salaries as for a normal key when switched on),
--      and says unattended; the normal key answers the same whatever the settings, without unattended.
--   4. Every refused function refuses the unattended key as it refuses a wrong one ({"ok": false, "error": "bad key"}):
--      capture_fare_actions(), capture_fare_actions_by_airline(), capture_eval_runs(), capture_eval_result(), and
--      capture_scan() and capture_market() while their settings are false; the normal key gets past the key's check.
--   5. The dispatch on the copy posts nothing (pg_net's queue unchanged) and writes its row: failed "no GitHub token in
--      the vault"; with a token but no project address, failed "not the live project"; with both and a capture page 5
--      minutes old, ok "skipped: a capture is running". GitHub's answer is noted on the row: 204 ok, 401 failed with
--      its words. private.schedule_jobs() lists the start at 09:30 and 21:30 UTC and the answer at 09:40 and 21:40 UTC.
--   6. system_status()'s unattended part: the setting; an old ok row as the last run and the last good run; a failed row
--      after it as the last run, the good one kept; the dispatch's last row. (Today and Systems with no row, an old ok
--      row and a failed row: tests/planner_next_test.py on the copy, and the planner's unit tests.)

create temporary table t_un (k text primary key, v jsonb) on commit drop;
grant select, insert on t_un to anon;

-- ---------------------------------------------------------------- 1. the catalogue
do $test$
declare bad text; f regprocedure;
  fns regprocedure[] := array['private.capture_key_issue(bigint, text, boolean)', 'private.capture_key_unattended(text)',
    'private.capture_unattended_allows(bigint, text)', 'private.capture_dispatch(timestamptz)', 'private.capture_dispatch_answer()']::regprocedure[];
begin
  assert (select a.atttypid = 'boolean'::regtype and a.attnotnull and pg_get_expr(d.adbin, d.adrelid) = 'false'
                 and length(coalesce(col_description(a.attrelid, a.attnum), '')) > 50
            from pg_attribute a left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
           where a.attrelid = 'public.capture_keys'::regclass and a.attname = 'unattended'),
    'capture_keys.unattended isn''t a described boolean, not null, default false';
  assert not exists (select 1 from public.capture_keys k where k.unattended), 'a key the copy has is marked unattended';
  assert position('unattended' in coalesce(obj_description('public.capture_keys'::regclass, 'pg_class'), '')) > 0,
    'capture_keys'' description doesn''t say a key may be unattended';
  -- job_runs takes the two new jobs, and still refuses one it doesn't know
  perform private.job_run_add('capture_unattended', null, now() - interval '400 days', 'ok', 'catalogue check', null);
  perform private.job_run_add('capture_dispatch', null, now() - interval '400 days', 'ok', 'catalogue check', null);
  begin
    perform private.job_run_add('capture_nothing', null, now() - interval '400 days', 'ok', 'catalogue check', null);
    raise exception 'job_runs took a job it doesn''t know';
  exception when check_violation then null;
  end;
  -- the settings: every world, described, with since and reason
  select string_agg(x.k || ' in ' || w.name, ', ') into bad
    from public.worlds w
   cross join (values ('unattended_salaries'), ('unattended_scan'), ('unattended_market'), ('capture_unattended_warn_h')) x(k)
   where not exists (select 1 from public.settings s where s.world_id = w.id and s.airline_id is null and s.key = x.k
                        and length(coalesce(s.description, '')) > 100 and s.since is not null and coalesce(s.reason, '') <> '');
  assert bad is null, 'settings missing or undescribed: ' || bad;
  assert (select string_agg(s.key || '=' || s.value::text, ', ' order by s.key) from public.settings s
           where s.world_id = (select id from public.worlds where is_default) and s.airline_id is null
             and s.key in ('unattended_salaries', 'unattended_scan', 'unattended_market', 'capture_unattended_warn_h'))
         = 'capture_unattended_warn_h=14, unattended_market=true, unattended_salaries=false, unattended_scan=true',
    'the default world''s settings aren''t 14, true, false and true';
  assert (select s.unit from public.settings s where s.world_id = (select id from public.worlds where is_default)
            and s.airline_id is null and s.key = 'capture_unattended_warn_h') = 'hours', 'capture_unattended_warn_h isn''t in hours';
  assert not exists (select 1 from public.settings s where s.airline_id is not null
                      and s.key in ('unattended_salaries', 'unattended_scan', 'unattended_market', 'capture_unattended_warn_h')),
    'an airline has its own unattended setting';
  -- the new functions: postgres only, run as the caller, empty search path, described
  foreach f in array fns loop
    assert not exists (select 1 from pg_proc p where p.oid = f
                         and (p.prosecdef or has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute')
                              or has_function_privilege('service_role', p.oid, 'execute') or not coalesce('search_path=""' = any (p.proconfig), false)
                              or exists (select 1 from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where a.grantee = 0)
                              or length(coalesce(obj_description(p.oid, 'pg_proc'), '')) < 60)),
      f::text || ' is open to others, runs as owner, has no empty search path or no description';
  end loop;
  assert exists (select 1 from pg_extension where extname = 'pg_net'), 'pg_net isn''t switched on';
  raise notice 'capture_keys.unattended (no key the copy has is unattended), job_runs takes capture_unattended and capture_dispatch, the four settings in every world (14, true, false, true), five new functions postgres''s only, pg_net on';
end
$test$;

-- ---------------------------------------------------------------- 2. issuing a key
do $test$
declare k text; n text; w bigint := (select id from public.worlds where is_default);
begin
  k := private.capture_key_issue(w, 'unattended capture test (unattended)', true);
  n := private.capture_key_issue(w, 'unattended capture test (normal)', false);
  assert k ~ '^[0-9a-f]{64}$' and n ~ '^[0-9a-f]{64}$' and k <> n, 'capture_key_issue() didn''t answer two different 64-character hex keys';
  assert private.capture_key_world(k) = w and private.capture_key_world(n) = w, 'capture_key_world() doesn''t accept the issued keys';
  assert private.capture_key_unattended(k) and not private.capture_key_unattended(n) and not private.capture_key_unattended('not the key')
     and not private.capture_key_unattended(null), 'capture_key_unattended() doesn''t tell the unattended key from the others';
  assert not exists (select 1 from public.capture_keys c where c.label like 'unattended capture test%' and (c.key_hash in (k, n) or c.key_hash !~ '^\$2[abxy]?\$')),
    'an issued key isn''t kept as its bf hash only';
  assert (select count(*) from public.capture_keys c where c.label = 'unattended capture test (unattended)' and c.unattended and c.world_id = w) = 1
     and (select count(*) from public.capture_keys c where c.label = 'unattended capture test (normal)' and not c.unattended and c.world_id = w) = 1,
    'the issued keys aren''t stored with their world, label and mark';
  begin
    perform private.capture_key_issue(-1, 'nowhere', true);
    raise exception 'capture_key_issue() issued a key for a world that doesn''t exist';
  exception when invalid_parameter_value then null;
  end;
  begin
    perform private.capture_key_issue(w, '  ', true);
    raise exception 'capture_key_issue() issued a key without a label';
  exception when invalid_parameter_value then null;
  end;
  insert into t_un values ('key_unattended', to_jsonb(k)), ('key_normal', to_jsonb(n));
  raise notice 'capture_key_issue(): a 64-character key capture_key_world() accepts, its bf hash only kept, marked as asked; a missing world or label refused';
end
$test$;

-- ---------------------------------------------------------------- 3. capture_airlines(), signed out
create or replace function pg_temp.un_set(p_key text, p_value jsonb) returns void language sql as $$
  update public.settings s set value = p_value
   where s.world_id = (select id from public.worlds where is_default) and s.airline_id is null and s.key = p_key
$$;

-- as the migration left them: no salaries, the scan and the market as for a normal key
set local role anon;
do $test$
begin
  insert into t_un values
    ('a_un', public.capture_airlines((select v #>> '{}' from t_un where k = 'key_unattended'))),
    ('a_n', public.capture_airlines((select v #>> '{}' from t_un where k = 'key_normal')));
end
$test$;
reset role;
do $set$ begin perform pg_temp.un_set('unattended_scan', 'false'::jsonb); perform pg_temp.un_set('unattended_market', 'false'::jsonb);
  perform pg_temp.un_set('unattended_salaries', 'true'::jsonb); end $set$;
set local role anon;
do $test$
begin
  insert into t_un values
    ('b_un', public.capture_airlines((select v #>> '{}' from t_un where k = 'key_unattended'))),
    ('b_n', public.capture_airlines((select v #>> '{}' from t_un where k = 'key_normal')));
end
$test$;
reset role;
do $set$ begin perform pg_temp.un_set('unattended_scan', 'true'::jsonb); perform pg_temp.un_set('unattended_market', 'true'::jsonb);
  perform pg_temp.un_set('unattended_salaries', 'false'::jsonb); end $set$;

do $test$
declare a jsonb := (select v from t_un where k = 'a_un'); an jsonb := (select v from t_un where k = 'a_n');
        b jsonb := (select v from t_un where k = 'b_un'); bn jsonb := (select v from t_un where k = 'b_n');
        plan_keys text[] := array['scan_due', 'scan_open', 'scan_every_days', 'scan_latest', 'scan_airports', 'market_due', 'market_open',
                                  'market_every_days', 'market_latest', 'market_total', 'market_done', 'market_pages', 'airlines', 'world'];
        x text;
begin
  assert an ->> 'ok' = 'true' and a ->> 'ok' = 'true', 'capture_airlines() refused an issued key: ' || coalesce(a ->> 'error', an ->> 'error', '?');
  -- the normal key: as before, whatever the settings
  assert not an ? 'unattended' and an = bn, 'the normal key''s answer changed with the unattended settings, or says unattended';
  assert an -> 'salary_above_average_pct' is not distinct from
         (select s.value from public.settings s where s.world_id = (select id from public.worlds where is_default) and s.airline_id is null
             and s.key = 'salary_above_average_pct'), 'the normal key''s salary_above_average_pct isn''t the setting';
  -- the unattended key, as the migration left the settings
  assert a -> 'unattended' = 'true'::jsonb and a ? 'salary_above_average_pct' and a -> 'salary_above_average_pct' = 'null'::jsonb,
    'with unattended_salaries false the unattended key gets salary_above_average_pct ' || coalesce(a ->> 'salary_above_average_pct', 'null') || ' or no unattended';
  foreach x in array plan_keys loop
    assert a -> x is not distinct from an -> x, 'with its settings true the unattended key''s ' || x || ' differs from the normal key''s';
  end loop;
  -- switched the other way
  assert b -> 'salary_above_average_pct' is not distinct from an -> 'salary_above_average_pct',
    'with unattended_salaries true the unattended key doesn''t get the normal key''s salaries';
  assert b -> 'scan_due' = 'false'::jsonb and b -> 'scan_open' = 'null'::jsonb, 'with unattended_scan false the scan is due or open for the unattended key';
  assert b -> 'market_due' = 'false'::jsonb and b -> 'market_open' = 'null'::jsonb and b -> 'market_pages' = '[]'::jsonb,
    'with unattended_market false the market pages are due, open or listed for the unattended key';
  assert b -> 'airlines' = an -> 'airlines' and b -> 'scan_airports' = an -> 'scan_airports', 'the unattended key''s airlines or airports changed with the settings';
  raise notice 'capture_airlines(): the unattended key gets no salaries, the scan (due %) and the market pages (due %) as the normal key; switched off, neither is due; salaries switched on, the normal key''s; the normal key unchanged',
    an ->> 'scan_due', an ->> 'market_due';
end
$test$;

-- ---------------------------------------------------------------- 4. the refused functions
do $test$
declare k text := (select t.v #>> '{}' from t_un t where t.k = 'key_unattended'); n text := (select t.v #>> '{}' from t_un t where t.k = 'key_normal');
        refused constant jsonb := '{"ok": false, "error": "bad key"}'; r jsonb;
begin
  assert public.capture_fare_actions(k) = refused, 'capture_fare_actions() doesn''t refuse the unattended key';
  assert public.capture_fare_actions_by_airline(k) = refused and public.capture_fare_actions_by_airline(k, 1) = refused,
    'capture_fare_actions_by_airline() doesn''t refuse the unattended key';
  assert public.capture_eval_runs(k) = refused, 'capture_eval_runs() doesn''t refuse the unattended key';
  assert public.capture_eval_result(k, -1, '{}'::jsonb) = refused, 'capture_eval_result() doesn''t refuse the unattended key';
  -- the normal key gets past the key's check (the list of airlines; a run that isn't there; a kind that isn't one)
  assert public.capture_fare_actions_by_airline(n) ->> 'ok' = 'true', 'capture_fare_actions_by_airline() refuses the normal key';
  r := public.capture_eval_runs(n);
  assert r is distinct from refused, 'capture_eval_runs() refuses the normal key';
  assert public.capture_eval_result(n, -1, '{}'::jsonb) ->> 'error' like 'run -1 isn''t on%', 'capture_eval_result() refuses the normal key';
  -- the scan and the market pages: refused only while their setting is false; a kind that isn't one tells which
  assert public.capture_scan(k, 'nonsense', '{}'::jsonb) ->> 'error' = 'bad kind' and public.capture_market(k, 'nonsense', '{}'::jsonb) ->> 'error' = 'bad kind',
    'capture_scan() or capture_market() refuses the unattended key while its setting is true';
  perform pg_temp.un_set('unattended_scan', 'false'::jsonb);
  perform pg_temp.un_set('unattended_market', 'false'::jsonb);
  assert public.capture_scan(k, 'start', '{}'::jsonb) = refused, 'capture_scan() doesn''t refuse the unattended key with unattended_scan false';
  assert public.capture_market(k, 'start', '{}'::jsonb) = refused, 'capture_market() doesn''t refuse the unattended key with unattended_market false';
  assert public.capture_scan(n, 'nonsense', '{}'::jsonb) ->> 'error' = 'bad kind' and public.capture_market(n, 'nonsense', '{}'::jsonb) ->> 'error' = 'bad kind',
    'capture_scan() or capture_market() refuses the normal key with the unattended settings false';
  perform pg_temp.un_set('unattended_scan', 'true'::jsonb);
  perform pg_temp.un_set('unattended_market', 'true'::jsonb);
  raise notice 'the unattended key refused by capture_fare_actions(), capture_fare_actions_by_airline(), capture_eval_runs() and capture_eval_result(), and by capture_scan() and capture_market() only while switched off; the normal key unchanged';
end
$test$;

-- ---------------------------------------------------------------- 5. the dispatch on the copy
do $test$
declare q0 bigint; r jsonb; j record; w bigint := (select id from public.worlds where is_default); vault_ok boolean := true;
        net_ok boolean := true; id401 bigint; id204 bigint;
begin
  begin
    select count(*) into q0 from net.http_request_queue;
  exception when insufficient_privilege then
    raise notice 'pg_net''s queue can''t be read here, so "posts nothing" rests on the rows: none says it asked GitHub';
  end;
  -- a copy's vault is empty: no token, no address
  assert not exists (select 1 from vault.decrypted_secrets s where s.name in ('github_dispatch_token', 'project_url')),
    'the copy''s vault holds the GitHub token or the project''s address';
  r := private.capture_dispatch();
  select * into j from public.job_runs x where x.job = 'capture_dispatch' order by x.id desc limit 1;
  assert r ->> 'status' = 'failed' and j.status = 'failed' and j.note = 'no GitHub token in the vault' and j.world_id = w,
    'with no token the dispatch didn''t write a failed row "no GitHub token in the vault": ' || coalesce(j.note, 'no row');
  -- a token, but not this project's address
  begin
    perform vault.create_secret('not-a-real-token', 'github_dispatch_token');
  exception when others then
    vault_ok := false;
    raise notice 'the copy''s vault can''t take a test secret here (%), so the address check is tested only without one', sqlerrm;
  end;
  if vault_ok then
    r := private.capture_dispatch();
    select * into j from public.job_runs x where x.job = 'capture_dispatch' order by x.id desc limit 1;
    assert j.status = 'failed' and j.note like 'not the live project: the vault''s project_url is missing%',
      'with a token but no project address the dispatch didn''t refuse: ' || coalesce(j.note, 'no row');
    perform vault.create_secret('https://example.invalid', 'project_url');
    r := private.capture_dispatch();
    select * into j from public.job_runs x where x.job = 'capture_dispatch' order by x.id desc limit 1;
    assert j.status = 'failed' and j.note like 'not the live project: the vault''s project_url is https://example.invalid,%',
      'with another project''s address the dispatch didn''t refuse: ' || coalesce(j.note, 'no row');
    -- this project's address, and a capture page 5 minutes ago: skipped
    perform vault.update_secret(s.id, 'https://ulecwsyedvwcxgdzmhoq.supabase.co') from vault.secrets s where s.name = 'project_url';
    insert into public.game_capture_raw (world_id, airline_id, airline, kind, page_url, rows, captured_at)
    select r0.world_id, r0.airline_id, r0.airline, 'html', '/rehearsal/unattended-skip', '[]'::jsonb, now() - interval '5 minutes'
      from public.game_capture_raw r0 where r0.world_id = w order by r0.id desc limit 1;
    if found then
      r := private.capture_dispatch();
      select * into j from public.job_runs x where x.job = 'capture_dispatch' order by x.id desc limit 1;
      assert j.status = 'ok' and j.note like 'skipped: a capture is running%' and (j.details ->> 'skipped')::boolean,
        'with a capture page 5 minutes ago the dispatch didn''t skip: ' || coalesce(j.note, 'no row');
    end if;
  end if;
  if q0 is not null then
    assert (select count(*) from net.http_request_queue) = q0, 'the dispatch queued a post on the copy';
  end if;
  assert not exists (select 1 from public.job_runs x where x.job = 'capture_dispatch' and x.details ? 'request_id'
                        and x.started_at > now() - interval '1 minute'), 'the dispatch says it asked GitHub from the copy';

  -- GitHub's answer, noted on the dispatch's row (pg_net's answers made by hand, ids no request has)
  begin
    insert into net._http_response (id, status_code, content, timed_out, error_msg, created)
    values (-424201, 401, '{"message": "Bad credentials"}', false, null, now()), (-424204, 204, '', false, null, now());
  exception when others then
    net_ok := false;
    raise notice 'pg_net''s answers can''t be written here (%), so noting the answer is tested only with none', sqlerrm;
  end;
  id401 := private.job_run_add('capture_dispatch', w, now() - interval '30 minutes', 'ok', 'asked GitHub (test)', jsonb_build_object('request_id', -424201));
  id204 := private.job_run_add('capture_dispatch', w, now() - interval '29 minutes', 'ok', 'asked GitHub (test)', jsonb_build_object('request_id', -424204));
  r := private.capture_dispatch_answer();
  if net_ok then
    assert (select status = 'failed' and note = 'GitHub answered 401: {"message": "Bad credentials"}' and details -> 'answer' = '401'::jsonb
              from public.job_runs where id = id401), 'a 401 isn''t noted as failed with GitHub''s words';
    assert (select status = 'ok' and note like 'GitHub started the unattended capture (204%' and details -> 'answer' = '204'::jsonb
              from public.job_runs where id = id204), 'a 204 isn''t noted as ok';
  else
    assert (select status = 'ok' and not details ? 'answer' from public.job_runs where id = id401), 'an answer not yet come was noted';
  end if;

  -- the schedule: the start at 09:30 and 21:30 UTC, its answer ten minutes later
  r := private.schedule_jobs();
  assert r @> '[{"job": "equinox-capture-dispatch", "schedule": "30 9,21 * * *", "command": "select private.capture_dispatch()"},
                {"job": "equinox-capture-dispatch-answer", "schedule": "40 9,21 * * *", "command": "select private.capture_dispatch_answer()"}]'::jsonb,
    'private.schedule_jobs() doesn''t list the unattended capture''s start and answer: ' || r::text;
  raise notice 'the dispatch on the copy posts nothing (pg_net''s queue unchanged): no token, failed; % ; GitHub''s answer noted (%); schedule_jobs() lists it at 09:30 and 21:30 UTC, the answer at 09:40 and 21:40',
    case when vault_ok then 'a token without this project''s address, failed; this project''s address with a capture running, skipped' else 'the vault took no test secret' end,
    case when net_ok then '401 failed, 204 ok' else 'none made' end;
end
$test$;

-- ---------------------------------------------------------------- 6. system_status()'s unattended part
do $test$
declare d jsonb; w bigint := (select id from public.worlds where is_default); t0 timestamptz := now() + interval '1 day';
begin
  -- a moment ahead of everything the copy has; the test's rows are put after it
  d := public.system_status(w, t0) -> 'unattended';
  assert d -> 'warn_h' = '14'::jsonb, 'system_status()''s unattended part lacks the setting: ' || coalesce(d::text, 'none');
  perform private.job_run_add('capture_unattended', w, t0 + interval '1 hour', 'ok', '6 airlines all good · 3 min 10 s', null);
  d := public.system_status(w, t0 + interval '16 hours') -> 'unattended';
  assert d #>> '{last,status}' = 'ok' and d #>> '{last_ok,at}' = private.fig_ts(t0 + interval '1 hour') and d #>> '{last,note}' = '6 airlines all good · 3 min 10 s',
    'an old ok row isn''t the last run and the last good run: ' || d::text;
  perform private.job_run_add('capture_unattended', w, t0 + interval '13 hours', 'failed', 'Pan Am: loads 12 of 78 flights', null);
  perform private.job_run_add('capture_dispatch', w, t0 + interval '12 hours 59 minutes', 'ok', 'asked GitHub (test)', null);
  d := public.system_status(w, t0 + interval '16 hours') -> 'unattended';
  assert d #>> '{last,status}' = 'failed' and d #>> '{last,note}' = 'Pan Am: loads 12 of 78 flights' and d #>> '{last_ok,at}' = private.fig_ts(t0 + interval '1 hour'),
    'a failed row isn''t the last run, with the last good run before it: ' || d::text;
  assert d #>> '{dispatch,at}' = private.fig_ts(t0 + interval '12 hours 59 minutes') and d #>> '{dispatch,status}' = 'ok',
    'the dispatch''s last run isn''t there: ' || d::text;
  raise notice 'system_status()''s unattended part: the setting (14), an old ok row as the last good run, a failed row after it as the last run, the dispatch''s last run';
end
$test$;

-- The website and scripts on the tables (#13 build, pull request 8; design §8, "The website and scripts keep their
-- outputs exactly"): what they get is what they got before the pending changes. Compares against the outputs
-- database/tests/before/website_scripts_before.sql saved before the migrations ran (rehearsal_before). Run by
-- database/rehearse.sh on the copy of last night's backup, inside a transaction that is rolled back. A failed check
-- stops with an error that says where (paths and counts, never values).
--   1. site_public(): exactly the same, apart from its new airlines key and updated_at; the 6 Oct limits hold (no
--      bank or transfer times, cabin layouts or aircraft on order) and airlines is our active airlines;
--   2. site_investor() (a throwaway password) and site_report() for one report: the same, except that cash and
--      next-7-day costs are now the getter's, so they may differ from the old row only as the side by side allowed
--      (the capture's figure for a date captured after the planner last saved, or one the saved document doesn't have
--      yet);
--   3. export_for_report('planner'): the same two documents, with only the differences the side by side allowed
--      (design §9: savedAt and version, a missing key equals null, numbers by value, flight numbers as text, a tail
--      with no status equals "Active", and the cash and next-7-day ones above);
--   4. export_planner_data(): the same. (export_capture() is compared in capture_data_compat_test.sql; site_admin() has
--      no read kinds.)
-- Each allowed difference used is printed with how often.
-- The "before" outputs come from the old rows when last night's backup is older than pull request 8, and those lag
-- behind the capture. The switch-over (pull request 9) made the side by side's comparison strict, so this test keeps
-- its own copy of the comparison as pull request 5 left it (pg_temp.old_rows_check), for outputs made from the old rows.

create function pg_temp.old_rows_check(p_world_id bigint, p_old jsonb, p_saved_at bigint, p_new jsonb)
 returns table (path text, kind text, why text)
 language sql
 stable
as $function$
  with d as (select x.path, x.kind from private.planner_json_diff(p_old, p_new) x),
  x as (
    select d.path, m[1] as sec, m[2] as day, m[3] as airline
      from d cross join lateral regexp_match(d.path, '^\$\.(cash|fixed7)\.([^.]+)(?:\.(.+))?$') as m
     where d.kind = 'differs' and m is not null),
  -- every entry behind a difference there, one per airline and date (a whole date differs when one side has none)
  entries as (
    select x.path, x.sec, x.day, x.airline from x where x.airline is not null
    union
    select x.path, x.sec, x.day, k.airline from x
      cross join lateral (select jsonb_object_keys(case when jsonb_typeof(p_new #> array[x.sec, x.day]) = 'object' then p_new #> array[x.sec, x.day] else '{}'::jsonb end)
                          union
                          select jsonb_object_keys(case when jsonb_typeof(p_old #> array[x.sec, x.day]) = 'object' then p_old #> array[x.sec, x.day] else '{}'::jsonb end)) as k(airline)
     where x.airline is null),
  money as (
    select e.path, e.sec, e.day, e.airline, p_old #> array[e.sec, e.day, e.airline] as had, p_new #> array[e.sec, e.day, e.airline] as got,
           cc.cash_at,
           case when e.sec = 'cash' then floor(cc.cash / 10000 + 0.5) / 100
                when cc.fixed_next7 > 0 then floor(cc.fixed_next7 / 10000 + 0.5) / 100 end as figure,
           (select max(ev.captured_at) from public.game_events ev
             where ev.airline_id = cc.airline_id and ev.debit > 0
               and ev.due_at > cc.cash_at and ev.due_at <= cc.cash_at + interval '7 days') as events_at
      from entries e
      left join public.airlines al on al.planner_name = e.airline and al.world_id = p_world_id
      left join public.capture_cash cc on cc.airline_id = al.id and cc.day = private.json_date(to_jsonb(e.day))),
  -- how each entry is allowed: 'late' (captured after the planner last saved), 'not saved' (the saved document has no
  -- entry), or not at all (null)
  judged as (
    select m.*,
           case when not coalesce(jsonb_typeof(m.got) = 'number' and m.figure is not null and (m.got #>> '{}')::numeric = m.figure, false) then null
                when m.cash_at > to_timestamp(p_saved_at / 1000.0)
                     or (m.sec = 'fixed7' and m.events_at > to_timestamp(p_saved_at / 1000.0)) then 'late'
                when coalesce(m.had, 'null'::jsonb) = 'null'::jsonb then 'not saved' end as how
      from money m)
  select d.path, d.kind, null::text from d where d.kind <> 'differs'
  union all
  select d.path,
         case when not exists (select 1 from judged j where j.path = d.path)
                   or exists (select 1 from judged j where j.path = d.path and j.how is null) then 'differs'
              when exists (select 1 from judged j where j.path = d.path and j.how = 'late') then 'cash/fixed7 captured after the planner last saved'
              else 'cash/fixed7 captured, not in the saved document' end,
         (select string_agg(format('%s %s %s (%s; %s)', j.sec, j.day, j.airline,
                   case when j.had is null then 'only in the tables' when j.got is null then 'only in planner_state' else 'the figure differs' end,
                   case when j.cash_at is null then 'no capture that date'
                        when j.figure is distinct from (case when jsonb_typeof(j.got) = 'number' then (j.got #>> '{}')::numeric end) then 'not the capture''s figure'
                        when j.cash_at > to_timestamp(p_saved_at / 1000.0) then 'captured after the planner last saved'
                        else 'captured before the planner last saved' end), ', ' order by j.sec, j.day, j.airline)
            from judged j where j.path = d.path and j.how is null)
    from d where d.kind = 'differs'
$function$;


do $test$
declare
  w bigint := (select id from public.worlds where is_default);
  s text := 'website-test-' || gen_random_uuid();
  pw text; r bigint; v_saved bigint; a jsonb; b jsonb; bad text; used text; why text; n_months int; v_keys text;
begin
  assert to_regclass('rehearsal_before.site_outputs') is not null,
    'the outputs from before the changes weren''t saved (database/tests/before/website_scripts_before.sql)';
  pw := (select value #>> '{}' from rehearsal_before.site_outputs where name = 'password');
  r := (select (value #>> '{}')::bigint from rehearsal_before.site_outputs where name = 'report id');
  v_saved := (select (value #>> '{}')::bigint from rehearsal_before.site_outputs where name = 'planner_state saved_at');
  insert into public.ingest_secret (secret) values (s);
  delete from public.report_access;   -- never in the backup; a throwaway password for this test only
  insert into public.report_access (pass_hash) values (extensions.crypt(pw, extensions.gen_salt('bf')));

  -- ---------------------------------------------------------------- 1. site_public()
  a := public.site_public();
  b := (select value from rehearsal_before.site_outputs where name = 'site_public');
  -- (a backup taken after pull request 8 already has the airlines key: then it must be the same too)
  if (a - array['airlines', 'updated_at']) is distinct from (b - array['airlines', 'updated_at'])
     or (b ? 'airlines' and a -> 'airlines' is distinct from b -> 'airlines') then
    select string_agg(x.place || ' (' || x.kind || ') ×' || x.n, ', ' order by x.place) into bad
      from (select private.planner_place(d.path) as place, d.kind, count(*) as n
              from private.planner_json_diff(b - 'updated_at' - case when b ? 'airlines' then '' else 'airlines' end,
                                             a - 'updated_at' - case when b ? 'airlines' then '' else 'airlines' end) d group by 1, 2) x;
    raise exception 'site_public() differs from before, apart from airlines and updated_at, at: %', coalesce(bad, 'the whole answer');
  end if;
  assert jsonb_typeof(a -> 'updated_at') = 'string', 'site_public() has no updated_at';
  -- the 6 Oct limits: nothing but these keys, and these fields in each list
  select string_agg(k, ', ') into bad from jsonb_object_keys(a) k
   where k not in ('updated_at', 'airlines', 'hubs', 'tails', 'freqs', 'interline', 'posts', 'reports', 'content');
  assert bad is null, 'site_public() gives more than before: ' || bad;
  select string_agg(distinct x.list || '.' || x.k, ', ') into bad
    from (select 'hubs' as list, k from jsonb_array_elements(a -> 'hubs') e, jsonb_object_keys(e) k where k not in ('code', 'airline', 'role')
          union all
          select 'tails', k from jsonb_array_elements(a -> 'tails') e, jsonb_object_keys(e) k where k not in ('id', 'airline', 'type')
          union all
          select 'freqs', k from jsonb_array_elements(a -> 'freqs') e, jsonb_object_keys(e) k
           where k not in ('r', 't', 'a', 'b', 'c', 'd', 'days', 'o', 'k', 'l')
          union all
          select 'airlines', k from jsonb_array_elements(a -> 'airlines') e, jsonb_object_keys(e) k
           where k not in ('key', 'name', 'code', 'color', 'slug', 'region', 'role', 'blurb', 'photo', 'position')) x;
  assert bad is null, 'site_public() lists fields it shouldn''t (no banks, cabins or aircraft on order): ' || bad;
  -- airlines: our active airlines, in position order, each with a key the rest of the feed uses
  select string_agg(coalesce(e ->> 'key', '?') || ' / ' || coalesce(al.planner_name, '?'), ', ') into bad
    from (select e, o from jsonb_array_elements(a -> 'airlines') with ordinality x(e, o)) j
    full join (select al.planner_name, row_number() over (order by al.position nulls last, al.id) as o
                 from public.airlines al join public.groups g on g.id = al.group_id and g.world_id = al.world_id
                where al.world_id = w and g.kind = 'ours' and al.active and al.planner_name is not null) al on al.o = j.o
   where e ->> 'key' is distinct from al.planner_name
      or e ->> 'name' is null or e ->> 'code' is null or e ->> 'color' is null or e ->> 'slug' is null;
  assert bad is null, 'site_public()''s airlines aren''t our active airlines in order, each with name, code, colour and slug: ' || bad;
  select string_agg(e ->> 'key', ', ') into v_keys from jsonb_array_elements(a -> 'airlines') e;
  raise notice 'site_public(): the same as before apart from airlines (% airlines: %) and updated_at; % hubs, % aircraft, % frequencies, % signed interlines, % connection times',
    jsonb_array_length(a -> 'airlines'), v_keys, jsonb_array_length(a -> 'hubs'), jsonb_array_length(a -> 'tails'),
    jsonb_array_length(a -> 'freqs'), jsonb_array_length(a -> 'interline'),
    (select count(*) from jsonb_object_keys(coalesce(a -> 'content' -> 'mct', '{}'::jsonb)));

  -- ---------------------------------------------------------------- 2. site_investor() and site_report()
  a := public.site_investor(pw);
  b := (select value from rehearsal_before.site_outputs where name = 'site_investor');
  assert a ->> 'ok' = 'true' and b ->> 'ok' = 'true', 'site_investor() didn''t take the throwaway password, before or after';
  select string_agg(private.planner_place(c.path) || coalesce(' (' || c.why || ')', ''), ', ' order by c.path) into bad
    from pg_temp.old_rows_check(w, jsonb_build_object('cash', b -> 'cash', 'fixed7', b -> 'fixed7'), v_saved,
                                     jsonb_build_object('cash', a -> 'cash', 'fixed7', a -> 'fixed7')) c
   where c.kind = 'differs';
  assert bad is null, 'site_investor()''s cash or next-7-day costs differ from before by more than the side by side allowed: ' || bad;
  select string_agg(private.planner_place(d.path), ', ' order by d.path) into bad
    from private.planner_json_diff(b - array['cash', 'fixed7'], a - array['cash', 'fixed7']) d where d.kind = 'differs';
  assert bad is null, 'site_investor() differs from before at: ' || bad;
  select string_agg(x.kind || ' ×' || x.n, '; ' order by x.kind) into used
    from (select c.kind, count(*) as n
            from (select c.kind from pg_temp.old_rows_check(w, jsonb_build_object('cash', b -> 'cash', 'fixed7', b -> 'fixed7'), v_saved,
                                                                  jsonb_build_object('cash', a -> 'cash', 'fixed7', a -> 'fixed7')) c
                  union all
                  select d.kind from private.planner_json_diff(b - array['cash', 'fixed7'], a - array['cash', 'fixed7']) d) c
           group by 1) x;
  assert public.site_report(r, pw) is not distinct from (select value from rehearsal_before.site_outputs where name = 'site_report'),
    'site_report() differs from before';
  assert public.site_investor(pw || 'x') = '{"ok": false}'::jsonb, 'site_investor() answers a wrong password';
  raise notice 'site_investor(): the same as before (% money-spent entries, % cash dates); allowed differences used: %. site_report(): the same (%)',
    jsonb_array_length(a -> 'capex'), (select count(*) from jsonb_object_keys(coalesce(a -> 'cash', '{}'::jsonb))), coalesce(used, 'none'),
    case when r is null then 'no published report in the copy: the empty answer compared' else 'report ' || r end;

  -- ---------------------------------------------------------------- 3. export_for_report('planner')
  a := public.export_for_report(s, 'planner');
  b := (select value from rehearsal_before.site_outputs where name = 'export_for_report planner');
  assert (select array_agg(k order by k) from jsonb_object_keys(a) k) = '{loads,state}', 'export_for_report(''planner'') isn''t {state, loads}';
  select string_agg(x.place || ' ×' || x.n, ', ' order by x.place), string_agg(x.why, '; ') into bad, why
    from (select private.planner_place(c.path) as place, count(*) as n, string_agg(c.why, '; ') as why
            from pg_temp.old_rows_check(w, b -> 'state', v_saved, a -> 'state') c where c.kind = 'differs' group by 1) x;
  assert bad is null, 'export_for_report(''planner'') state differs from before at: ' || bad || coalesce('; cash and next-7-day figures: ' || why, '');
  select string_agg(coalesce(o.key, n.key), ', ') into bad
    from jsonb_each(b -> 'loads') o full join jsonb_each(a -> 'loads') n on n.key = o.key where o.key is null or n.key is null;
  assert bad is null, 'export_for_report(''planner'') loads don''t have the same months as before: ' || bad;
  select string_agg(x.place || ' ×' || x.n, ', ' order by x.place) into bad
    from (select private.planner_place(d.path) as place, count(*) as n
            from jsonb_each(b -> 'loads') o join jsonb_each(a -> 'loads') n on n.key = o.key
            cross join lateral private.planner_json_diff(o.value, n.value) d where d.kind = 'differs' group by 1) x;
  assert bad is null, 'export_for_report(''planner'') loads differ from before at: ' || bad;
  select count(*) into n_months from jsonb_object_keys(a -> 'loads');
  select string_agg(x.kind || ' ×' || x.n, '; ' order by x.kind) into used
    from (select y.kind, count(*) as n
            from (select c.kind from pg_temp.old_rows_check(w, b -> 'state', v_saved, a -> 'state') c
                  union all
                  select d.kind from jsonb_each(b -> 'loads') o join jsonb_each(a -> 'loads') n on n.key = o.key
                         cross join lateral private.planner_json_diff(o.value, n.value) d) y
           group by 1) x;

  -- ---------------------------------------------------------------- 4. export_planner_data()
  assert public.export_planner_data(s) = (select value from rehearsal_before.site_outputs where name = 'export_planner_data'),
    'export_planner_data() differs from before';
  raise notice 'export_for_report(''planner''): the same state and loads (% months) as before; allowed differences used: %. export_planner_data(): the same',
    n_months, coalesce(used, 'none');
  delete from public.ingest_secret where secret = s;
end
$test$;

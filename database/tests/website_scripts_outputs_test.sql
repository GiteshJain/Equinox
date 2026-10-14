-- The website on the tables (#13 build, pull request 8; design §8, "The website and scripts keep their outputs
-- exactly"; off the adapter since the clean-up, #18 build pull request 14): what it gets is what it got before the
-- pending changes. Compares against the outputs database/tests/before/website_scripts_before.sql saved before the
-- migrations ran (rehearsal_before). Run by database/rehearse.sh on the copy of last night's backup, inside a transaction
-- that is rolled back. A failed check stops with an error that says where (keys and counts, never values).
--   1. site_public(): exactly the same apart from updated_at (which may only move on, with the changes' own writes) and
--      the order of the aircraft flying (tails): the same aircraft, in the order the planner's Tails lists them (by when
--      they were added) since the clean-up, which counted the old list's places (the count of those that moved is
--      printed). content.connection_max_wait_h is the world's setting; the 6 Oct limits hold (no bank or transfer times,
--      cabin layouts or aircraft on order) and airlines is our active airlines, in order.
--   2. site_investor() (a throwaway password) and site_report() for one report: exactly the same, cash and next-7-day
--      costs included (worked out in site_investor() since the clean-up, as planner_state_get() worked them out).
-- (export_for_report()'s scans are compared in history_scans_test.sql, its figures in clean_up_test.sql.)

do $test$
declare
  w bigint := (select id from public.worlds where is_default);
  pw text; r bigint; a jsonb; b jsonb; bad text; v_keys text; n_moved int;
begin
  assert to_regclass('rehearsal_before.site_outputs') is not null,
    'the outputs from before the changes weren''t saved (database/tests/before/website_scripts_before.sql)';
  pw := (select value #>> '{}' from rehearsal_before.site_outputs where name = 'password');
  r := (select (value #>> '{}')::bigint from rehearsal_before.site_outputs where name = 'report id');
  delete from public.report_access;   -- never in the backup; a throwaway password for this test only
  insert into public.report_access (pass_hash) values (extensions.crypt(pw, extensions.gen_salt('bf')));

  -- ---------------------------------------------------------------- 1. site_public()
  a := public.site_public();
  b := (select value from rehearsal_before.site_outputs where name = 'site_public');
  assert a -> 'content' -> 'connection_max_wait_h' is not distinct from
         (select to_jsonb((s.value #>> '{}')::numeric) from public.settings s
           where s.world_id = w and s.airline_id is null and s.key = 'connection_max_wait_h'),
    'site_public()''s content.connection_max_wait_h isn''t the world''s connection_max_wait_h setting';
  select string_agg(k, ', ' order by k) into bad
    from (select k from jsonb_object_keys(a) k union select k from jsonb_object_keys(b) k) x(k)
   where k not in ('updated_at', 'tails') and a -> k is distinct from b -> k;
  assert bad is null, 'site_public() differs from before (apart from updated_at and the aircraft''s order) at: ' || bad;
  assert (select jsonb_agg(e order by e::text) from jsonb_array_elements(a -> 'tails') e)
         is not distinct from (select jsonb_agg(e order by e::text) from jsonb_array_elements(b -> 'tails') e),
    format('site_public() lists other aircraft flying than before (%s now, %s before)', jsonb_array_length(a -> 'tails'), jsonb_array_length(b -> 'tails'));
  select count(*) into n_moved
    from jsonb_array_elements(a -> 'tails') with ordinality x(e, i)
    join jsonb_array_elements(b -> 'tails') with ordinality y(e, i) on y.i = x.i
   where x.e is distinct from y.e;
  assert jsonb_typeof(a -> 'updated_at') = 'string' and (a ->> 'updated_at')::timestamptz >= (b ->> 'updated_at')::timestamptz,
    'site_public()''s updated_at is missing or earlier than before';
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
  -- the aircraft flying: those in service, in the order they were added
  assert (select jsonb_agg(e ->> 'id' order by i) from jsonb_array_elements(a -> 'tails') with ordinality x(e, i))
         is not distinct from (select jsonb_agg(ac.registration order by ac.id) from public.aircraft ac
                                 join public.airlines al on al.id = ac.airline_id
                                where ac.world_id = w and ac.status = 'active'),
    'site_public()''s aircraft flying aren''t those in service, in the order they were added';
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
  raise notice 'site_public(): the same as before apart from updated_at (% airlines: %); % hubs, % aircraft (% in another place than before), % frequencies, % signed interlines, % connection times',
    jsonb_array_length(a -> 'airlines'), v_keys, jsonb_array_length(a -> 'hubs'), jsonb_array_length(a -> 'tails'), n_moved,
    jsonb_array_length(a -> 'freqs'), jsonb_array_length(a -> 'interline'),
    (select count(*) from jsonb_object_keys(coalesce(a -> 'content' -> 'mct', '{}'::jsonb)));

  -- ---------------------------------------------------------------- 2. site_investor() and site_report()
  a := public.site_investor(pw);
  b := (select value from rehearsal_before.site_outputs where name = 'site_investor');
  assert a ->> 'ok' = 'true' and b ->> 'ok' = 'true', 'site_investor() didn''t take the throwaway password, before or after';
  select string_agg(k, ', ' order by k) into bad
    from (select k from jsonb_object_keys(a) k union select k from jsonb_object_keys(b) k) x(k)
   where a -> k is distinct from b -> k;
  assert bad is null, 'site_investor() differs from before at: ' || bad;
  assert public.site_report(r, pw) is not distinct from (select value from rehearsal_before.site_outputs where name = 'site_report'),
    'site_report() differs from before';
  assert public.site_investor(pw || 'x') = '{"ok": false}'::jsonb, 'site_investor() answers a wrong password';
  raise notice 'site_investor(): exactly as before (% money-spent entries, % cash dates, % next-7-day dates). site_report(): the same (%)',
    jsonb_array_length(a -> 'capex'), (select count(*) from jsonb_object_keys(coalesce(a -> 'cash', '{}'::jsonb))),
    (select count(*) from jsonb_object_keys(coalesce(a -> 'fixed7', '{}'::jsonb))),
    case when r is null then 'no published report in the copy: the empty answer compared' else 'report ' || r end;
end
$test$;

-- The adapter's read side against today's planner_state (#13 build, pull request 4; design §8, §9). Run by
-- database/rehearse.sh on the copy of last night's backup, after the new migrations, inside a transaction that is rolled
-- back. A failed check stops with an error that says where (paths and counts, never values).
-- planner_state_get() equals planner_state with only the differences design §9 allows; each allowed difference used is
-- printed with how often. A cash or next-7-day figure that differs is named (date and airline), with the side that has
-- it and whether the capture's balance came after the planner last saved: the planner copies a capture in only when it
-- next opens, while the getter shows the capture's figure at once (design §8).

-- the differences between two documents, by where they are: list positions as [], keys of keyed sections as {}
create function pg_temp.places(p_old jsonb, p_new jsonb) returns table (kind text, place text, n bigint) language sql as $$
  select d.kind,
         regexp_replace(regexp_replace(regexp_replace(regexp_replace(d.path, '\[\d+\]', '[]', 'g'),
           '^(\$\.(plans|cash|fixed7|interline|routeEdits|routeCabin|monthly|dismissed|cabinKeep|ref\.markets|ref\.curfews|ref\.gameLinks|ref\.utcOverrides))\.[^.\[]+', '\1.{}'),
           '^\$\.\d{4}-\d{2}-\d{2}', '$.{day}'), '\.f\..+$', '.f.{flight}'),
         count(*)
    from private.planner_json_differences(p_old, p_new) d
   group by 1, 2
$$;

do $test$
declare v_old jsonb; v_new jsonb; bad text; cash_why text; used text;
begin
  select p.json::jsonb into v_old from public.planner_state p where p.id = 'main';
  assert v_old is not null, 'the copy has no planner_state row to compare with';
  v_new := (public.planner_state_get() ->> 'json')::jsonb;
  select string_agg(place || ' ×' || n, ', ' order by place) into bad from pg_temp.places(v_old, v_new) where kind = 'differs';
  -- a cash or next-7-day figure: which date and airline, which side has it, and whether the capture's balance came
  -- after the planner last saved (the planner copies a capture in only when it next opens)
  if bad is not null then
    -- (a whole date differs when one side has none of its figures)
    select '; cash and next-7-day figures: ' || string_agg(format('%s %s %s (%s%s)', x.m[1], x.m[2], coalesce(x.m[3], 'every airline'),
             case when x.m[3] is null and not coalesce(v_old -> x.m[1] ? x.m[2], false) then 'only in the getter'
                  when x.m[3] is null and not coalesce(v_new -> x.m[1] ? x.m[2], false) then 'only in planner_state'
                  when x.m[3] is null then 'the figures differ'
                  when not coalesce(v_old -> x.m[1] -> x.m[2] ? x.m[3], false) then 'only in the getter'
                  when not coalesce(v_new -> x.m[1] -> x.m[2] ? x.m[3], false) then 'only in planner_state' else 'the figure differs' end,
             coalesce((select format('; %s of %s airlines'' balances captured after the planner last saved',
                                     count(*) filter (where cc.cash_at > to_timestamp(p.saved_at / 1000.0)), count(*))
                         from public.capture_cash cc join public.airlines al on al.id = cc.airline_id
                         cross join public.planner_state p
                        where p.id = 'main' and (x.m[3] is null or al.planner_name = x.m[3]) and cc.day::text = x.m[2]
                       having count(*) > 0), '; no capture that date')), ', ')
      into cash_why
      from (select regexp_match(d.path, '^\$\.(cash|fixed7)\.([^.]+)(?:\.(.+))?$') as m
              from private.planner_json_differences(v_old, v_new) d where d.kind = 'differs') x
     where x.m is not null;
    bad := bad || coalesce(cash_why, '');
  end if;
  assert bad is null, 'planner_state_get() differs from planner_state at: ' || bad;
  select string_agg(kind || ' ×' || n || ' (' || places || ')', '; ' order by kind) into used
    from (select kind, sum(n) as n, string_agg(place, ', ' order by place) as places from pg_temp.places(v_old, v_new) group by kind) x;
  raise notice 'planner_state_get() equals planner_state (% tails, % frequencies, % plan cards, % to-dos); allowed differences used: %',
    jsonb_array_length(v_old -> 'tails'), jsonb_array_length(v_old -> 'freqs'),
    (select count(*) from jsonb_object_keys(v_old -> 'plans')), jsonb_array_length(v_old -> 'todos'), coalesce(used, 'none');
end
$test$;

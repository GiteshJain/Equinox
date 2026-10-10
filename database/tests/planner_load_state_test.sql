-- The adapter's read side against today's planner_state (#13 build, pull request 4; design §8, §9). Run by
-- database/rehearse.sh on the copy of last night's backup, after the new migrations, inside a transaction that is rolled
-- back. A failed check stops with an error that says where (paths and counts, never values).
-- planner_state_get() equals planner_state with only the differences design §9 allows, plus one more (the Building
-- chat's call, 10 Oct, inside design §8): "cash/fixed7 captured after the planner last saved". The getter shows the
-- capture's figures at once (design §8), while the planner copies a capture in only when it next opens
-- (applyCaptureCash), so a copy taken between a capture and the planner's next opening differs there. It is allowed
-- only for a cash or fixed7 entry of an airline and date
--   - whose getter figure equals the capture's (capture_cash, rounded as the planner rounds), so a wrong number fails;
--   - and whose capture came after planner_state's last save: for cash, that airline's balance for the date; for
--     fixed7, that balance (the 7 days are counted from it, so the planner can't have worked the figure out before it
--     existed) or any of the events the figure counts.
-- Each allowed difference used is printed with how often. Any other difference fails, and a cash or next-7-day figure
-- that fails is named (date and airline) with the side that has it and when it was captured.

-- a difference's place: list positions as [], keys of keyed sections as {}
create function pg_temp.place(p_path text) returns text language sql immutable as $$
  select regexp_replace(regexp_replace(p_path, '\[\d+\]', '[]', 'g'),
           '^(\$\.(plans|cash|fixed7|interline|routeEdits|routeCabin|monthly|dismissed|cabinKeep|ref\.markets|ref\.curfews|ref\.gameLinks|ref\.utcOverrides))\.[^.\[]+', '\1.{}')
$$;

do $test$
declare v_old jsonb; v_new jsonb; v_saved timestamptz; bad text; cash_why text; used text; v_late bigint; v_late_places text;
begin
  select p.json::jsonb, to_timestamp(p.saved_at / 1000.0) into v_old, v_saved from public.planner_state p where p.id = 'main';
  assert v_old is not null, 'the copy has no planner_state row to compare with';
  v_new := (public.planner_state_get() ->> 'json')::jsonb;
  create temporary table t_diff on commit drop as
    select d.path, d.kind from private.planner_json_differences(v_old, v_new) d;

  -- every cash or fixed7 entry behind a difference there, one per airline and date (a whole date differs when one side
  -- has none of its figures), judged against the capture
  create temporary table t_money on commit drop as
  with x as (
    select t.path, m[1] as sec, m[2] as day, m[3] as airline
      from t_diff t cross join lateral regexp_match(t.path, '^\$\.(cash|fixed7)\.([^.]+)(?:\.(.+))?$') as m
     where t.kind = 'differs' and m is not null),
  entries as (
    select x.path, x.sec, x.day, x.airline from x where x.airline is not null
    union
    select x.path, x.sec, x.day, k.airline from x
      cross join lateral (select jsonb_object_keys(case when jsonb_typeof(v_new #> array[x.sec, x.day]) = 'object' then v_new #> array[x.sec, x.day] else '{}'::jsonb end)
                          union
                          select jsonb_object_keys(case when jsonb_typeof(v_old #> array[x.sec, x.day]) = 'object' then v_old #> array[x.sec, x.day] else '{}'::jsonb end)) as k(airline)
     where x.airline is null)
  select e.path, e.sec, e.day, e.airline, v_old #> array[e.sec, e.day, e.airline] as had, v_new #> array[e.sec, e.day, e.airline] as got,
         cc.cash_at,
         case when e.sec = 'cash' then floor(cc.cash / 10000 + 0.5) / 100
              when cc.fixed_next7 > 0 then floor(cc.fixed_next7 / 10000 + 0.5) / 100 end as figure,
         (select max(ev.captured_at) from public.game_events ev
           where ev.airline_id = cc.airline_id and ev.debit > 0
             and ev.due_at > cc.cash_at and ev.due_at <= cc.cash_at + interval '7 days') as events_at
    from entries e
    left join public.airlines al on al.planner_name = e.airline and al.world_id = (select id from public.worlds where is_default)
    left join public.capture_cash cc on cc.airline_id = al.id and cc.day = private.json_date(to_jsonb(e.day));
  alter table t_money add column late boolean;
  update t_money set late = jsonb_typeof(got) = 'number' and figure is not null and (got #>> '{}')::numeric = figure
                            and (cash_at > v_saved or (sec = 'fixed7' and events_at > v_saved));

  -- what remains: every other difference, and any cash or fixed7 path with an entry that isn't allowed
  select string_agg(pg_temp.place(t.path) || ' ×' || t.n, ', ' order by pg_temp.place(t.path)) into bad
    from (select d.path, count(*) as n from t_diff d
           where d.kind = 'differs'
             and (not exists (select 1 from t_money m where m.path = d.path)
                  or exists (select 1 from t_money m where m.path = d.path and not m.late))
           group by d.path) t;
  if bad is not null then
    select '; cash and next-7-day figures: ' || string_agg(format('%s %s %s (%s; %s)', m.sec, m.day, m.airline,
             case when m.had is null then 'only in the getter' when m.got is null then 'only in planner_state' else 'the figure differs' end,
             case when m.cash_at is null then 'no capture that date'
                  when m.figure is distinct from (case when jsonb_typeof(m.got) = 'number' then (m.got #>> '{}')::numeric end) then 'not the capture''s figure'
                  when m.cash_at > v_saved then 'captured after the planner last saved'
                  else 'captured before the planner last saved' end), ', ' order by m.sec, m.day, m.airline)
      into cash_why
      from t_money m where not m.late;
    bad := bad || coalesce(cash_why, '');
  end if;
  assert bad is null, 'planner_state_get() differs from planner_state at: ' || bad;

  select count(*), string_agg(distinct '$.' || sec || '.{}.{}', ', ') into v_late, v_late_places from t_money where late;
  select string_agg(x.kind || ' ×' || x.n || ' (' || x.places || ')', '; ' order by x.kind) into used
    from (select y.kind, sum(y.n) as n, string_agg(y.place, ', ' order by y.place) as places
            from (select d.kind, pg_temp.place(d.path) as place, count(*) as n from t_diff d where d.kind <> 'differs' group by 1, 2
                  union all
                  select 'cash/fixed7 captured after the planner last saved', v_late_places, v_late where v_late > 0) y
           group by y.kind) x;
  raise notice 'planner_state_get() equals planner_state (% tails, % frequencies, % plan cards, % to-dos); allowed differences used: %',
    jsonb_array_length(v_old -> 'tails'), jsonb_array_length(v_old -> 'freqs'),
    (select count(*) from jsonb_object_keys(v_old -> 'plans')), jsonb_array_length(v_old -> 'todos'), coalesce(used, 'none');
end
$test$;

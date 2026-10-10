-- The capture's entry points and completeness by world (#13 build, pull request 3; design §2, §3.8, §7).
-- Run by database/rehearse.sh on the copy of last night's backup, after the new migrations, inside a transaction that
-- is rolled back. A failed check stops with an error that says which.
--   1. capture_airlines() with the key gives the key's world and its active airlines of our groups; a wrong key gets
--      nothing.
--   2. capture_ingest(): by game ID (the new userscript) and by today's names (the old userscript and the bookmark),
--      signed out like the userscript; refused: a wrong key, a wrong kind, an airline of another world (and nothing is
--      stored for it); a key of another world can't send our airlines' pages.
--   3. The capture day (design §2): 10:00 UTC to 10:00 UTC, named after the evening.
--   4. Completeness by world (design §7): a day is complete when every active airline of our groups has all five pages;
--      a 7th active airline makes it incomplete until it is captured too. A loads day's done follows (design §8's one
--      rule, public.loads_day_captured): in planner_loads_get(), and in the capture's loads step, run with the freeze
--      lifted as a rollback lifts it (since the switch-over, #13 pull request 9, it leaves the frozen planner_loads
--      alone). A day already done stays done in planner_loads.

create temporary table t_i (k text primary key, v text) on commit drop;
grant select on t_i to anon;

do $setup$
declare w bigint; w2 bigint; g2 bigint;
begin
  select id into w from public.worlds where is_default;
  insert into public.capture_keys (label, key_hash, world_id)
  values ('ingest test', extensions.crypt('ingest-test-key', extensions.gen_salt('bf')), w);
  -- another world, with its own group, airline and key
  insert into public.worlds (name, game_host, kind) values ('Ingest test world', 'ingest-test.example', 'short_term') returning id into w2;
  insert into public.groups (world_id, name, kind) values (w2, 'ingest test group', 'ours') returning id into g2;
  insert into public.airlines (world_id, group_id, game_id, planner_name, active) values (w2, g2, 999777, 'Other World Air', true);
  insert into public.capture_keys (label, key_hash, world_id)
  values ('ingest test, other world', extensions.crypt('ingest-test-key-2', extensions.gen_salt('bf')), w2);
  insert into t_i values ('world', w::text);
end
$setup$;

-- ---------------------------------------------------------------- 1 and 2, signed out like the userscript
set local role anon;
do $test$
declare r jsonb; ids int[];
begin
  r := public.capture_airlines('not the key');
  assert r ->> 'ok' = 'false' and not r ? 'airlines', 'a wrong key got airlines: ' || r::text;
  r := public.capture_airlines('ingest-test-key');
  assert r ->> 'ok' = 'true' and r ->> 'world' = 'Gander', 'capture_airlines() didn''t answer for Gander: ' || r::text;
  select array_agg((a ->> 'game_id')::int order by (a ->> 'game_id')::int) into ids from jsonb_array_elements(r -> 'airlines') a;
  assert ids @> array[112, 113, 114, 203, 208, 210] and not 999777 = any (ids),
    'capture_airlines() gave the wrong airlines: ' || ids::text;

  r := public.capture_ingest('ingest-test-key', '113', 'pnl', '/test', '[["Ingest test line", "1,234 AS$", "1,000 AS$", "9,999 AS$"]]');
  assert r ->> 'ok' = 'true' and r ->> 'airline' = 'Kingfisher' and r ->> 'rows' = '1' and r ? 'capture_day' and r ? 'day_complete',
    'a page sent with the game ID wasn''t taken: ' || r::text;
  r := public.capture_ingest('ingest-test-key', 'Kingfisher', 'pnl', '/test', '[["Ingest test line 2", "5 AS$", "5 AS$", "5 AS$"]]');
  assert r ->> 'ok' = 'true' and r ->> 'airline' = 'Kingfisher', 'a page sent with today''s name wasn''t taken: ' || r::text;
  r := public.capture_ingest('ingest-test-key', 'Pan Am World Airways', 'pnl', '/test', '[["Ingest test line 3", "5 AS$", "5 AS$", "5 AS$"]]');
  assert r ->> 'ok' = 'true' and r ->> 'airline' = 'Pan American', 'a page sent with the game''s name wasn''t taken: ' || r::text;

  r := public.capture_ingest('not the key', '113', 'pnl', '/test', '[]');
  assert r ->> 'ok' = 'false' and r ->> 'error' = 'bad key', 'a wrong key wasn''t refused: ' || r::text;
  r := public.capture_ingest('ingest-test-key', '113', 'gossip', '/test', '[]');
  assert r ->> 'ok' = 'false' and r ->> 'error' = 'bad kind', 'a wrong kind wasn''t refused: ' || r::text;
  r := public.capture_ingest('ingest-test-key', '999777', 'pnl', '/test', '[["Ingest test line 4", "5 AS$", "5 AS$", "5 AS$"]]');
  assert r ->> 'ok' = 'false', 'a page for an airline of another world was taken: ' || r::text;
  r := public.capture_ingest('ingest-test-key-2', '113', 'pnl', '/test', '[["Ingest test line 5", "5 AS$", "5 AS$", "5 AS$"]]');
  assert r ->> 'ok' = 'false', 'another world''s key sent a page for one of Gander''s airlines: ' || r::text;
  r := public.capture_ingest('ingest-test-key', 'Unknown Air', 'pnl', '/test', '[]');
  assert r ->> 'ok' = 'false', 'a page for an unknown airline was taken: ' || r::text;
end
$test$;
reset role;

do $test$
declare n bigint;
begin
  select count(*) into n from public.game_pnl p join public.airlines a on a.id = p.airline_id
   where p.line in ('Ingest test line', 'Ingest test line 2') and a.game_id = 113 and p.world_id = a.world_id
     and p.capture_day = private.capture_day(p.world_id, p.captured_at);
  assert n = 2, format('the pages for Kingfisher wrote %s of their 2 rows with its ids and capture day', n);
  assert exists (select 1 from public.game_pnl where line = 'Ingest test line 3' and airline = 'Pan American'), 'the page for Pan Am wasn''t written';
  assert not exists (select 1 from public.game_pnl where line in ('Ingest test line 4', 'Ingest test line 5')), 'a refused page was written';
  assert not exists (select 1 from public.game_capture_raw r join public.airlines a on a.id = r.airline_id where a.game_id = 999777),
    'a refused page was stored';
end
$test$;

-- ---------------------------------------------------------------- 3 and 4
do $test$
declare w bigint := (select v::bigint from t_i where k = 'world'); kf bigint; al7 bigint; d date := '2099-05-01'; today date;
  r record; mon text; j jsonb;
begin
  -- 3. the capture day
  assert private.capture_day(w, '2099-05-01 10:00+00') = '2099-05-01' and private.capture_day(w, '2099-05-02 09:59+00') = '2099-05-01'
     and private.capture_day(w, '2099-05-01 09:59+00') = '2099-04-30', 'the capture day doesn''t run 10:00 to 10:00 UTC';

  -- 4. a day with all five pages for each of our active airlines
  insert into public.game_capture_raw (world_id, airline_id, airline, kind, rows, captured_at)
  select a.world_id, a.id, a.planner_name, k.kind, '[]', d + time '22:30' at time zone 'UTC'
    from public.airlines a join public.groups g on g.id = a.group_id
    cross join (values ('statement'), ('events'), ('pnl'), ('balance'), ('loads')) k (kind)
   where a.world_id = w and a.active and g.kind = 'ours';
  assert private.capture_day_complete(w, d), 'a day with all five pages for every airline isn''t complete';
  assert not private.capture_day_complete(w, d + 1), 'a day with no pages is complete';
  -- one page missing
  delete from public.game_capture_raw where id = (select max(id) from public.game_capture_raw where kind = 'balance' and captured_at = d + time '22:30' at time zone 'UTC');
  assert not private.capture_day_complete(w, d), 'a day with a page missing is complete';
  insert into public.game_capture_raw (world_id, airline_id, airline, kind, rows, captured_at)
  select a.world_id, a.id, a.planner_name, 'balance', '[]', d + time '23:30' at time zone 'UTC'
    from public.airlines a join public.groups g on g.id = a.group_id
   where a.world_id = w and a.active and g.kind = 'ours';
  assert private.capture_day_complete(w, d), 'the day isn''t complete again once the page came';

  -- a 7th airline: the day isn't complete until it is captured too
  insert into public.airlines (world_id, group_id, game_id, planner_name, iata_code, active)
  select w, g.id, 999007, 'Seventh Air', 'SV', true from public.groups g where g.world_id = w and g.kind = 'ours' order by g.id limit 1
  returning id into al7;
  assert not private.capture_day_complete(w, d), 'a day is complete without the 7th airline''s pages';
  insert into public.game_capture_raw (world_id, airline_id, airline, kind, rows, captured_at)
  select w, al7, 'Seventh Air', k.kind, '[]', d + time '23:45' at time zone 'UTC'
    from (values ('statement'), ('events'), ('pnl'), ('balance'), ('loads')) k (kind);
  assert private.capture_day_complete(w, d), 'the day isn''t complete once the 7th airline was captured';

  -- a loads day's done follows: a day (today, so the loads step looks at it) not done until the 7th airline is in; the
  -- getter and the capture's loads step agree (the loads step writes planner_loads only with the freeze lifted)
  if private.planner_frozen_since('public.planner_loads'::regclass) is not null then perform private.unfreeze_planner_state(); end if;
  today := (now() at time zone 'UTC')::date; mon := to_char(today, 'YYYY-MM');
  select id into kf from public.airlines where world_id = w and game_id = 113;
  delete from public.game_capture_raw where captured_at >= private.capture_day_start(w, today) and captured_at < private.capture_day_start(w, today) + interval '1 day';
  update public.planner_loads set json = (json::jsonb - today::text)::text where month = mon;
  delete from public.load_days where world_id = w and game_date = today;
  insert into public.game_flights (world_id, airline_id, game_date, flight_no, dep_local, eco_pct, loads_captured_at)
  values (w, kf, today, 9901, '23:59', 50, now()) on conflict do nothing;
  insert into public.game_capture_raw (world_id, airline_id, airline, kind, rows, captured_at)
  select a.world_id, a.id, a.planner_name, k.kind, '[]', private.capture_day_start(w, today) + interval '12 hours'
    from public.airlines a join public.groups g on g.id = a.group_id
    cross join (values ('statement'), ('events'), ('pnl'), ('balance'), ('loads')) k (kind)
   where a.world_id = w and a.active and g.kind = 'ours' and a.id <> al7;
  perform private.apply_loads_from_capture(kf);
  select json::jsonb into j from public.planner_loads where month = mon;
  assert j #> array[today::text, 'done'] = 'false'::jsonb, 'planner_loads marks a day done without the 7th airline: ' || coalesce(j #>> array[today::text, 'done'], 'missing');
  assert j #> array[today::text, 'f', 'Kingfisher|9901'] = '50'::jsonb, 'the loads step didn''t add the flight';
  assert (select g.json::jsonb #> array[today::text, 'done'] from public.planner_loads_get(w) g where g.month = mon) = 'false'::jsonb,
    'planner_loads_get() marks a day done without the 7th airline';
  insert into public.game_capture_raw (world_id, airline_id, airline, kind, rows, captured_at)
  select w, al7, 'Seventh Air', k.kind, '[]', private.capture_day_start(w, today) + interval '13 hours'
    from (values ('statement'), ('events'), ('pnl'), ('balance'), ('loads')) k (kind);
  perform private.apply_loads_from_capture(kf);
  select json::jsonb into j from public.planner_loads where month = mon;
  assert j #> array[today::text, 'done'] = 'true'::jsonb, 'planner_loads doesn''t mark the day done once every airline is in';
  assert (select g.json::jsonb #> array[today::text, 'done'] from public.planner_loads_get(w) g where g.month = mon) = 'true'::jsonb,
    'planner_loads_get() doesn''t mark the day done once every airline is in';
  -- a day already done stays done
  delete from public.game_capture_raw where airline_id = al7;
  perform private.apply_loads_from_capture(kf);
  select json::jsonb into j from public.planner_loads where month = mon;
  assert j #> array[today::text, 'done'] = 'true'::jsonb, 'a day already done went back to not done';
end
$test$;

do $$ begin raise notice 'capture entry points and completeness: all checks passed'; end $$;

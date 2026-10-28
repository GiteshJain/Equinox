-- The aircraft evaluation script's run list and results (27 Oct 2026; spec docs/specs/2026-10-27-aircraft-evaluation-script.md,
-- the Building chat's design).
--
-- Why (Gitesh, 27 Oct): the default line (manual §3) picks variants by the game's published ranges, at full load with
-- each type's maximum seats; our cabins carry fewer seats and the game flies them further. The game's aircraft
-- evaluation tool shows, for a route, what every type would earn and whether it can fly it at all. A userscript in the
-- game (capture/aircraft_eval.user.js) runs the tool over about 520 routes, one after another, while Gitesh watches,
-- and saves what it shows here. The Scheduling chat writes the run list with plain SQL and reads the results as
-- postgres; nothing in the planner or the website reads them.
--
-- Adds two tables, one setting in every world and two functions; changes, drops and renames nothing, so it can be
-- applied from the chat:
--   - public.aircraft_eval_runs: the run list, one row per route and seat type, in order (pass, seq), with the header
--     the script writes back (the names the tool resolved, the settings the page showed, done_at).
--   - public.aircraft_eval_results: one row per run and aircraft type, every figure the tool's table showed, parsed
--     and as text.
--   - settings aircraft_eval_types (world-level, in every world): the 17 types each run must show, by the tool's names.
--   - public.capture_eval_runs(p_key): with the capture key, the runs still without a result, and the types.
--   - public.capture_eval_result(p_key, p_run, p_doc): with the capture key, saves one run's result.
-- Both tables: RLS on with one staff read rule, staff read only (manual §1, "a new table grants its own access"),
-- nothing for the website; only the two functions (as owner) write them. The functions run as owner with an empty
-- search path, callable signed out and signed in, as capture_fare_actions().

select set_config('equinox.actor', 'migration', true),
       set_config('equinox.actor_detail', '20261027210000_aircraft_eval', true);

-- ============================================================ 1. the tables
create table public.aircraft_eval_runs (
  id bigint generated always as identity primary key,
  world_id bigint not null references public.worlds (id),
  pass integer not null check (pass between 1 and 4),
  seq integer not null,
  from_code text not null check (from_code ~ '^[A-Z0-9]{3}$'),
  to_code text not null check (to_code ~ '^[A-Z0-9]{3}$'),
  distance_km integer check (distance_km > 0),
  seat text not null check (seat in ('Standard', 'Leisure', 'Leisure Plus', 'Comfort')),
  note text,
  from_name text,
  to_name text,
  settings jsonb,
  done_at timestamptz,
  created_at timestamptz not null default now(),
  constraint aircraft_eval_runs_two_ends check (from_code <> to_code),
  constraint aircraft_eval_runs_world_seq_key unique (world_id, seq),
  constraint aircraft_eval_runs_route_seat_key unique (world_id, from_code, to_code, seat)
);

create table public.aircraft_eval_results (
  run_id bigint not null references public.aircraft_eval_runs (id) on delete cascade,
  type_name text not null check (type_name <> ''),
  game_type_id bigint,
  can_operate boolean not null,
  message text,
  flights_week numeric,
  seats numeric,
  fuel numeric,
  handling numeric,
  atc numeric,
  landing numeric,
  maintenance numeric,
  capital numeric,
  crew numeric,
  fixed_total numeric,
  per_seat numeric,
  profit_50 numeric,
  profit_60 numeric,
  profit_70 numeric,
  profit_80 numeric,
  profit_90 numeric,
  profit_100 numeric,
  margin_50 numeric,
  margin_60 numeric,
  margin_70 numeric,
  margin_80 numeric,
  margin_90 numeric,
  margin_100 numeric,
  cells jsonb not null check (jsonb_typeof(cells) = 'array'),
  saved_at timestamptz not null default clock_timestamp(),
  primary key (run_id, type_name),
  -- a type that can fly the route has every figure; one that can't has none
  constraint aircraft_eval_results_figures check (
    case when can_operate
         then num_nulls(flights_week, seats, fuel, handling, atc, landing, maintenance, capital, crew, fixed_total, per_seat,
                        profit_50, profit_60, profit_70, profit_80, profit_90, profit_100,
                        margin_50, margin_60, margin_70, margin_80, margin_90, margin_100) = 0
         else num_nonnulls(flights_week, seats, fuel, handling, atc, landing, maintenance, capital, crew, fixed_total, per_seat,
                           profit_50, profit_60, profit_70, profit_80, profit_90, profit_100,
                           margin_50, margin_60, margin_70, margin_80, margin_90, margin_100) = 0 end)
);
-- the run_id foreign key is the primary key's first column, and world_id the run list's (world_id, seq) key's: both indexed

alter table public.aircraft_eval_runs enable row level security;
alter table public.aircraft_eval_results enable row level security;
create policy "staff read" on public.aircraft_eval_runs for select to authenticated using ((select public.is_planner_user()));
create policy "staff read" on public.aircraft_eval_results for select to authenticated using ((select public.is_planner_user()));
revoke all on table public.aircraft_eval_runs from public, anon, authenticated;
revoke all on table public.aircraft_eval_results from public, anon, authenticated;
grant select on table public.aircraft_eval_runs to authenticated;
grant select on table public.aircraft_eval_results to authenticated;

-- ============================================================ 2. the setting
insert into public.settings (world_id, airline_id, key, value, unit, description, since, reason)
select w.id, null, 'aircraft_eval_types',
       '["Airbus A320NEO", "Airbus A320NEO Heavy", "Airbus A320NEO Light", "Airbus A320NEO SHARP", "Airbus A321LR",
         "Airbus A321NEO", "Airbus A321NEO Heavy", "Airbus A321NEO Light", "Airbus A321NEO Medium", "Airbus A321XLR",
         "Airbus A321XLR Heavy", "Airbus A321XLR Light", "Airbus A350-1000", "Airbus A350-900", "Airbus A350-900ULR",
         "Embraer 190 E2", "Embraer 195 E2"]'::jsonb,
       'types',
       'The aircraft evaluation script''s types (spec docs/specs/2026-10-27-aircraft-evaluation-script.md): a JSON list of the game''s aircraft evaluation tool''s own names for the types every run compares. The script adds any missing from the tool''s table before a run, capture_eval_runs() hands the list over, and capture_eval_result() refuses a result without a row for each. Change it with plain SQL (manual §1); no code change is needed.',
       date '2026-10-27',
       'Gitesh, 27 Oct: the default line''s 13 variants (manual §3) plus the A321neo Heavy and Medium and the A321XLR Heavy and Light, as he selected them in the tool'
  from public.worlds w
on conflict on constraint settings_world_airline_key_key do nothing;

-- ============================================================ 3. the functions
create or replace function public.capture_eval_runs(p_key text)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
declare v_world bigint; v_types jsonb;
begin
  v_world := private.capture_key_world(p_key);
  if v_world is null then return jsonb_build_object('ok', false, 'error', 'bad key'); end if;
  select s.value into v_types from public.settings s
   where s.world_id = v_world and s.airline_id is null and s.key = 'aircraft_eval_types';
  if v_types is null or jsonb_typeof(v_types) <> 'array' or jsonb_array_length(v_types) = 0 then
    return jsonb_build_object('ok', false, 'error', 'no aircraft_eval_types setting in this world');
  end if;
  return jsonb_build_object(
    'ok', true,
    'world', (select w.name from public.worlds w where w.id = v_world),
    'types', v_types,
    'total', (select count(*) from public.aircraft_eval_runs r where r.world_id = v_world),
    'done', (select count(*) from public.aircraft_eval_runs r where r.world_id = v_world and r.done_at is not null),
    'runs', coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'pass', r.pass, 'seq', r.seq, 'from', r.from_code,
                                                          'to', r.to_code, 'seat', r.seat) order by r.pass, r.seq)
                        from public.aircraft_eval_runs r where r.world_id = v_world and r.done_at is null), '[]'::jsonb));
end
$function$;

create or replace function public.capture_eval_result(p_key text, p_run bigint, p_doc jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_world bigint; v_seat text; v_types jsonb; v_rows jsonb; v_bad text; v_n integer;
  c_figs constant text[] := array['flights_week', 'seats', 'fuel', 'handling', 'atc', 'landing', 'maintenance', 'capital',
                                  'crew', 'fixed_total', 'per_seat', 'profit_50', 'profit_60', 'profit_70', 'profit_80',
                                  'profit_90', 'profit_100', 'margin_50', 'margin_60', 'margin_70', 'margin_80', 'margin_90',
                                  'margin_100'];
begin
  v_world := private.capture_key_world(p_key);
  if v_world is null then return jsonb_build_object('ok', false, 'error', 'bad key'); end if;
  select r.seat into v_seat from public.aircraft_eval_runs r where r.id = p_run and r.world_id = v_world;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'run ' || coalesce(p_run::text, '(none)') || ' isn''t on this world''s run list');
  end if;
  select s.value into v_types from public.settings s
   where s.world_id = v_world and s.airline_id is null and s.key = 'aircraft_eval_types';
  if v_types is null or jsonb_typeof(v_types) <> 'array' or jsonb_array_length(v_types) = 0 then
    return jsonb_build_object('ok', false, 'error', 'no aircraft_eval_types setting in this world');
  end if;
  if p_doc is null or jsonb_typeof(p_doc) <> 'object' or jsonb_typeof(p_doc -> 'rows') is distinct from 'array' then
    return jsonb_build_object('ok', false, 'error', 'the result has no rows');
  end if;
  if coalesce(btrim(p_doc ->> 'from_name'), '') = '' or coalesce(btrim(p_doc ->> 'to_name'), '') = '' then
    return jsonb_build_object('ok', false, 'error', 'the result doesn''t name the route''s two airports');
  end if;
  if jsonb_typeof(p_doc -> 'settings') is distinct from 'object' or p_doc -> 'settings' ->> 'seat' is distinct from v_seat then
    return jsonb_build_object('ok', false, 'error', 'the result''s seat is ' || coalesce(p_doc -> 'settings' ->> 'seat', 'not given')
                                                    || ', the run''s ' || v_seat);
  end if;
  v_rows := p_doc -> 'rows';

  -- each row: an object with its type's name, can_operate true or false, the game's type id a whole number or null,
  -- and its cells as a list
  select string_agg('row ' || e.i, ', ' order by e.i) into v_bad
    from jsonb_array_elements(v_rows) with ordinality as e(x, i)
   where jsonb_typeof(e.x) <> 'object' or jsonb_typeof(e.x -> 'type_name') is distinct from 'string'
      or btrim(e.x ->> 'type_name') = '' or jsonb_typeof(e.x -> 'can_operate') is distinct from 'boolean'
      or jsonb_typeof(e.x -> 'cells') is distinct from 'array'
      or coalesce(jsonb_typeof(e.x -> 'game_type_id'), 'null') not in ('null', 'number')
      or (jsonb_typeof(e.x -> 'game_type_id') = 'number' and (e.x ->> 'game_type_id') !~ '^[0-9]+$');
  if v_bad is not null then
    return jsonb_build_object('ok', false, 'error', v_bad || ': needs type_name, can_operate (true or false), cells and a whole game_type_id or none');
  end if;
  select string_agg(t.n, ', ' order by t.n) into v_bad
    from (select e.x ->> 'type_name' as n from jsonb_array_elements(v_rows) e(x) group by 1 having count(*) > 1) t;
  if v_bad is not null then return jsonb_build_object('ok', false, 'error', 'a type twice in the result: ' || v_bad); end if;

  -- every type of the setting has its row
  select string_agg(t.n, ', ' order by t.i) into v_bad
    from jsonb_array_elements_text(v_types) with ordinality as t(n, i)
   where not exists (select 1 from jsonb_array_elements(v_rows) e(x) where e.x ->> 'type_name' = t.n);
  if v_bad is not null then return jsonb_build_object('ok', false, 'error', 'the result has no row for ' || v_bad); end if;

  -- a type that can fly: every figure a number; one that can't: none
  select string_agg(e.x ->> 'type_name' || ': ' || f.k, ', ' order by e.i, f.j) into v_bad
    from jsonb_array_elements(v_rows) with ordinality as e(x, i)
    cross join unnest(c_figs) with ordinality as f(k, j)
   where (e.x ->> 'can_operate')::boolean and jsonb_typeof(e.x -> f.k) is distinct from 'number';
  if v_bad is not null then return jsonb_build_object('ok', false, 'error', 'not a number: ' || v_bad); end if;
  select string_agg(e.x ->> 'type_name' || ': ' || f.k, ', ' order by e.i, f.j) into v_bad
    from jsonb_array_elements(v_rows) with ordinality as e(x, i)
    cross join unnest(c_figs) with ordinality as f(k, j)
   where not (e.x ->> 'can_operate')::boolean and coalesce(jsonb_typeof(e.x -> f.k), 'null') <> 'null';
  if v_bad is not null then return jsonb_build_object('ok', false, 'error', 'a figure for a type that cannot operate: ' || v_bad); end if;

  -- replace any earlier result for the run
  delete from public.aircraft_eval_results r where r.run_id = p_run;
  insert into public.aircraft_eval_results (run_id, type_name, game_type_id, can_operate, message, flights_week, seats, fuel,
                                            handling, atc, landing, maintenance, capital, crew, fixed_total, per_seat,
                                            profit_50, profit_60, profit_70, profit_80, profit_90, profit_100,
                                            margin_50, margin_60, margin_70, margin_80, margin_90, margin_100, cells)
  select p_run, btrim(x ->> 'type_name'), (x ->> 'game_type_id')::bigint, (x ->> 'can_operate')::boolean,
         nullif(btrim(x ->> 'message'), ''),
         (x ->> 'flights_week')::numeric, (x ->> 'seats')::numeric, (x ->> 'fuel')::numeric, (x ->> 'handling')::numeric,
         (x ->> 'atc')::numeric, (x ->> 'landing')::numeric, (x ->> 'maintenance')::numeric, (x ->> 'capital')::numeric,
         (x ->> 'crew')::numeric, (x ->> 'fixed_total')::numeric, (x ->> 'per_seat')::numeric,
         (x ->> 'profit_50')::numeric, (x ->> 'profit_60')::numeric, (x ->> 'profit_70')::numeric,
         (x ->> 'profit_80')::numeric, (x ->> 'profit_90')::numeric, (x ->> 'profit_100')::numeric,
         (x ->> 'margin_50')::numeric, (x ->> 'margin_60')::numeric, (x ->> 'margin_70')::numeric,
         (x ->> 'margin_80')::numeric, (x ->> 'margin_90')::numeric, (x ->> 'margin_100')::numeric,
         x -> 'cells'
    from jsonb_array_elements(v_rows) e(x);
  get diagnostics v_n = row_count;
  update public.aircraft_eval_runs r
     set from_name = btrim(p_doc ->> 'from_name'), to_name = btrim(p_doc ->> 'to_name'), settings = p_doc -> 'settings',
         done_at = clock_timestamp()
   where r.id = p_run;
  return jsonb_build_object(
    'ok', true, 'run', p_run, 'saved', v_n,
    'done', (select count(*) from public.aircraft_eval_runs r where r.world_id = v_world and r.done_at is not null),
    'total', (select count(*) from public.aircraft_eval_runs r where r.world_id = v_world));
end
$function$;

revoke all on function public.capture_eval_runs(text) from public, anon, authenticated;
revoke all on function public.capture_eval_result(text, bigint, jsonb) from public, anon, authenticated;
grant execute on function public.capture_eval_runs(text) to anon, authenticated;
grant execute on function public.capture_eval_result(text, bigint, jsonb) to anon, authenticated;

-- ============================================================ 4. the descriptions
comment on table public.aircraft_eval_runs is 'The aircraft evaluation script''s run list (spec docs/specs/2026-10-27-aircraft-evaluation-script.md): one row per route and economy seat type to run through the game''s aircraft evaluation tool (/app/aircraft/evaluation), in order (pass, then seq), about 520 in all. The Scheduling chat writes the list with plain SQL (manual §1''s actor line); the script (capture/aircraft_eval.user.js) reads the runs without a result through capture_eval_runs() and writes each result''s header here through capture_eval_result(). Staff read it; not in the change log. Its results are aircraft_eval_results.';
comment on column public.aircraft_eval_runs.id is 'The run''s own number, which capture_eval_result() is given';
comment on column public.aircraft_eval_runs.world_id is 'The world whose capture key may run and save it';
comment on column public.aircraft_eval_runs.pass is 'The pass, 1 to 4: 1 the distance ladder, 2 a second region at each ladder distance, 3 real decisions (the November trunks and each airline''s top openings), 4 Ryanair on Standard seats';
comment on column public.aircraft_eval_runs.seq is 'The order within the world (unique): the script runs pass by pass, then by seq, shortest first within passes 1 to 3, so the seat type changes only twice';
comment on column public.aircraft_eval_runs.from_code is 'The route''s first airport, IATA, as typed into the tool''s From box';
comment on column public.aircraft_eval_runs.to_code is 'The route''s second airport, IATA, as typed into the tool''s To box';
comment on column public.aircraft_eval_runs.distance_km is 'The route''s distance, km, for the Scheduling chat; optional, the script doesn''t use it';
comment on column public.aircraft_eval_runs.seat is 'The economy seat type to run with, by the tool''s name: Standard, Leisure, Leisure Plus or Comfort (manual §5: by distance; Standard for Ryanair). The script sets the tool''s Seat to it before the run when it differs';
comment on column public.aircraft_eval_runs.note is 'A note from the Scheduling chat (why this route is on the list); optional';
comment on column public.aircraft_eval_runs.from_name is 'The first airport''s name as the tool resolved the code (written with the result)';
comment on column public.aircraft_eval_runs.to_name is 'The second airport''s name as the tool resolved the code (written with the result)';
comment on column public.aircraft_eval_runs.settings is 'The tool''s settings as the result page showed them, by their texts: age ("0 year(s)"), class ("Economy"), seat ("Comfort") and price_factor ("100%")';
comment on column public.aircraft_eval_runs.done_at is 'When its result was saved; null while it has none (capture_eval_runs() lists only those). A run saved again moves it on';
comment on column public.aircraft_eval_runs.created_at is 'When the run was put on the list';
comment on constraint aircraft_eval_runs_route_seat_key on public.aircraft_eval_runs is 'A route runs once per seat type in a world';

comment on table public.aircraft_eval_results is 'What the game''s aircraft evaluation tool showed for each aircraft type on a run (spec docs/specs/2026-10-27-aircraft-evaluation-script.md): one row per run and type, every figure of its row in the tool''s table, parsed as numbers and as the page showed them (cells), so nothing needs re-running if another figure turns out to matter. A type that can''t fly the route has can_operate false, the game''s message and no figures. Money is in AS$ a week, as the tool shows it. Written only by capture_eval_result(), which replaces a run''s rows when it is saved again; rows for types beyond settings.aircraft_eval_types are kept too. Staff read it; the Scheduling chat reads it as postgres.';
comment on column public.aircraft_eval_results.run_id is 'The run (aircraft_eval_runs); its rows go with it';
comment on column public.aircraft_eval_results.type_name is 'The type by the tool''s name, e.g. Airbus A350-900';
comment on column public.aircraft_eval_results.game_type_id is 'The game''s id of the type, from the link in the tool''s first cell (aircraftsType?id=3921)';
comment on column public.aircraft_eval_results.can_operate is 'Whether the type can fly the route; false when the tool says "This type cannot operate on the selected relation."';
comment on column public.aircraft_eval_results.message is 'The tool''s text for a type that cannot operate; null otherwise';
comment on column public.aircraft_eval_results.flights_week is 'Flights per week one aircraft can fly on the route (6.00)';
comment on column public.aircraft_eval_results.seats is 'Available seats with the run''s settings (the class and seat type)';
comment on column public.aircraft_eval_results.fuel is 'Fuel, AS$ a week';
comment on column public.aircraft_eval_results.handling is 'Aircraft handling, AS$ a week';
comment on column public.aircraft_eval_results.atc is 'ATC, AS$ a week';
comment on column public.aircraft_eval_results.landing is 'Landing fees, AS$ a week';
comment on column public.aircraft_eval_results.maintenance is 'Maintenance, AS$ a week';
comment on column public.aircraft_eval_results.capital is 'Capital cost, AS$ a week';
comment on column public.aircraft_eval_results.crew is 'Crew, AS$ a week';
comment on column public.aircraft_eval_results.fixed_total is 'Fixed costs total, AS$ a week';
comment on column public.aircraft_eval_results.per_seat is 'Fixed costs per seat, AS$ (539 AS$)';
comment on column public.aircraft_eval_results.profit_50 is 'Profit at 50% load, AS$ a week';
comment on column public.aircraft_eval_results.profit_60 is 'Profit at 60% load, AS$ a week';
comment on column public.aircraft_eval_results.profit_70 is 'Profit at 70% load, AS$ a week';
comment on column public.aircraft_eval_results.profit_80 is 'Profit at 80% load, AS$ a week';
comment on column public.aircraft_eval_results.profit_90 is 'Profit at 90% load, AS$ a week';
comment on column public.aircraft_eval_results.profit_100 is 'Profit at 100% load, AS$ a week';
comment on column public.aircraft_eval_results.margin_50 is 'Margin at 50% load, % (the bracket beside the profit)';
comment on column public.aircraft_eval_results.margin_60 is 'Margin at 60% load, %';
comment on column public.aircraft_eval_results.margin_70 is 'Margin at 70% load, %';
comment on column public.aircraft_eval_results.margin_80 is 'Margin at 80% load, %';
comment on column public.aircraft_eval_results.margin_90 is 'Margin at 90% load, %';
comment on column public.aircraft_eval_results.margin_100 is 'Margin at 100% load, %';
comment on column public.aircraft_eval_results.cells is 'Every cell of the type''s row as the page showed it, as text, the type''s cell first';
comment on column public.aircraft_eval_results.saved_at is 'When the row was saved';

comment on function public.capture_eval_runs(text) is 'For the aircraft evaluation script (capture/aircraft_eval.user.js; spec docs/specs/2026-10-27-aircraft-evaluation-script.md), with the capture key: the runs of the key''s world without a result (aircraft_eval_runs, done_at null) in pass, then seq order, each {id, pass, seq, from, to, seat}; types, the world''s settings.aircraft_eval_types (the tool''s names of the types every run compares); total, the runs on the list, and done, those with a result. {ok, world, types, total, done, runs}. A wrong or missing key gets {"ok": false, "error": "bad key"}, a world without the setting {"ok": false, "error": "no aircraft_eval_types setting in this world"}. Read only; runs as owner with an empty search path, callable signed out and signed in, as capture_fare_actions().';
comment on function public.capture_eval_result(text, bigint, jsonb) is 'For the aircraft evaluation script (capture/aircraft_eval.user.js; spec docs/specs/2026-10-27-aircraft-evaluation-script.md), with the capture key: saves one run''s result. p_doc is {from_name, to_name, settings: {age, class, seat, price_factor}, rows: [{type_name, game_type_id, can_operate, message, flights_week, seats, fuel, handling, atc, landing, maintenance, capital, crew, fixed_total, per_seat, profit_50 to profit_100, margin_50 to margin_100, cells}]}. Refuses, saving nothing ({"ok": false, "error": why}): a wrong key, a run not on the key''s world''s list, no route names, a seat other than the run''s, a row without its type, a type twice, no row for one of settings.aircraft_eval_types, a figure that isn''t a number for a type that can operate, or any figure for one that can''t. Saves rows for extra types too. Replaces any earlier result for the run (saving twice is no harm), writes the run''s from_name, to_name, settings and done_at, and answers {ok, run, saved (rows), done, total}. Runs as owner with an empty search path, callable signed out and signed in, as capture_fare_actions().';

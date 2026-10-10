-- The website and scripts read the tables (decision #13, build pull request 8).
-- Design: docs/design/2026-10-09-data-model.md (§3.13, §5, §8 "The website and scripts keep their outputs exactly").
-- Spec: docs/specs/2026-10-10-website-and-scripts.md.
--
-- Adds and changes; removes and revokes nothing that exists, so there is no separate file for Gitesh. Every function
-- keeps its name, arguments, callers and answer:
--   1. site_public(): hubs, aircraft, frequencies, signed interlines and content.mct from the tables, plus one new key,
--      airlines (names, codes, colours, the website's text, display order), from airlines. The 6 Oct limits stay: no
--      bank or transfer times, no cabin layouts, no aircraft on order;
--   2. site_investor(): cash and next-7-day costs as planner_state_get() gives them, money spent from spending_log;
--   3. export_for_report('planner'): {state, loads} from planner_state_get() and planner_loads_get(), unwrapped;
--   4. planner_data_set(): the route research also goes into countries, airports and routes (only the rows that
--      change), and still into planner_data, which the old planner reads until #18;
--   5. site_admin(): ('content', 'mct') also writes world_airports, the one copy of connection times that
--      site_public() reads; site_content.mct is still written, because the adapter falls back on it for a hub;
--   6. site_set_airline_logo(): checks the airline against airlines, not a list in its code;
--   7. access and descriptions.
-- site_report() reads no planner data and is unchanged. Nothing here changes planner_state, planner_loads, the planner
-- or the side by side (pull request 9 freezes the old rows).

select set_config('equinox.actor', 'migration', true),
       set_config('equinox.actor_detail', '20261010220000_website_and_scripts', true);

-- ============================================================ 1. site_public()
create or replace function public.site_public()
 returns jsonb
 language sql
 stable security definer
 set search_path to ''
as $function$
  with w as (select x.id from public.worlds x where x.is_default),
  -- each frequency as planner_state_get() gives it (the same joins and local times, design §4), in its order
  freqs as (
    select r.id, r.airline_id, ro.hub_code,
           jsonb_build_object(
             'routeKey', al.planner_name || '|' || ro.hub_code || '|' || ro.dest_code,
             'days', (select string_agg(d::text, '' order by d) from unnest(x.days_local) as d),
             'tail', coalesce(ac.registration, ''),
             'noOut', coalesce(l1.flight_no::text, ''),
             'noBack', coalesce(l2.flight_no::text, ''),
             'depHub', coalesce(to_char(make_time(x.dep_hub / 60, x.dep_hub % 60, 0), 'HH24:MI'), ''),
             'arrDest', coalesce(to_char(make_time(x.arr_dest / 60, x.arr_dest % 60, 0), 'HH24:MI'), ''),
             'depDest', coalesce(to_char(make_time(x.dep_dest / 60, x.dep_dest % 60, 0), 'HH24:MI'), ''),
             'arrHub', coalesce(to_char(make_time(x.arr_hub / 60, x.arr_hub % 60, 0), 'HH24:MI'), ''),
             'launched', r.launched_on::text)
           || r.extra as j
      from w
      join public.rotations r on r.world_id = w.id
      join public.routes ro on ro.id = r.route_id
      join public.airlines al on al.id = r.airline_id
      left join public.flight_legs l1 on l1.rotation_id = r.id and l1.leg_no = 1
      left join public.flight_legs l2 on l2.rotation_id = r.id and l2.leg_no = 2
      left join public.aircraft ac on ac.id = coalesce(l1.aircraft_id, l2.aircraft_id)
      left join public.airports ah on ah.code = ro.hub_code
      left join public.world_airports wh on wh.world_id = w.id and wh.airport_code = ro.hub_code
      left join public.airports ad on ad.code = ro.dest_code
      left join public.world_airports wd on wd.world_id = w.id and wd.airport_code = ro.dest_code
      -- each end's offset in minutes; an airport whose offset isn't known counts as UTC, as the planner counts it
      cross join lateral (select round(coalesce(wh.utc_offset_override, ah.utc_offset, 0) * 60)::int as oh,
                                 round(coalesce(wd.utc_offset_override, ad.utc_offset, 0) * 60)::int as od) o
      cross join lateral (
        select (((l1.dep_utc_min + o.oh) % 1440) + 1440) % 1440 as dep_hub,
               (((l1.dep_utc_min + l1.block_min + o.od) % 1440) + 1440) % 1440 as arr_dest,
               (((l2.dep_utc_min + o.od) % 1440) + 1440) % 1440 as dep_dest,
               (((l2.dep_utc_min + l2.block_min + o.oh) % 1440) + 1440) % 1440 as arr_hub,
               -- the old planner keeps the outbound's local weekdays at the hub
               dl.days_local
          from (select case when l1.dep_utc_min is null then l1.days_utc
                            else array(select distinct ((((d - 1 + floor((l1.dep_utc_min + o.oh) / 1440.0)::int) % 7) + 7) % 7 + 1)::smallint
                                         from unnest(l1.days_utc) as d order by 1) end as days_local) dl) x),
  -- each aircraft flying (a tail in the old planner), in the tails list's order
  tails as (
    select a.id, (a.extra ->> 'tails_index')::int as ord,
           jsonb_strip_nulls(jsonb_build_object('id', a.registration, 'airline', al.planner_name, 'type', coalesce(t.name, '')))
           || coalesce(a.extra -> 'tail', '{}'::jsonb) as j
      from w
      join public.aircraft a on a.world_id = w.id and a.extra ? 'tails_index'
      join public.airlines al on al.id = a.airline_id
      left join public.aircraft_types t on t.id = a.aircraft_type_id)
  select jsonb_build_object(
    -- when the planner's data last changed (planner_state_version())
    'updated_at', (select to_timestamp(nullif(public.planner_state_version(w.id), 0) / 1000.0) from w),
    -- our airlines in the world the website shows, in display order: what the website used to keep in its code
    'airlines', (select coalesce(jsonb_agg(jsonb_build_object(
                   'key', a.planner_name, 'name', a.public_name, 'code', a.iata_code, 'color', a.livery_color,
                   'slug', a.slug, 'region', a.region_text, 'role', a.role_text, 'blurb', a.blurb, 'photo', a.photo_city,
                   'position', a.position) order by a.position nulls last, a.id), '[]'::jsonb)
                   from w
                   join public.airlines a on a.world_id = w.id
                   join public.groups g on g.id = a.group_id and g.world_id = a.world_id
                  where g.kind = 'ours' and a.active and a.planner_name is not null),
    -- hubs and focus cities an airline of theirs flies from: code, airline and role only (no banks, no connection times)
    'hubs', (select coalesce(jsonb_agg(jsonb_build_object('code', b.airport_code, 'airline', al.planner_name, 'role', b.role)
                                       order by b.position, b.id), '[]'::jsonb)
               from w
               join public.airline_bases b on b.world_id = w.id
               join public.airlines al on al.id = b.airline_id
              where exists (select 1 from freqs f where f.airline_id = b.airline_id and f.hub_code = b.airport_code)),
    'tails', (select coalesce(jsonb_agg(jsonb_build_object('id', t.j ->> 'id', 'airline', t.j ->> 'airline', 'type', t.j ->> 'type')
                                        order by t.ord, t.id), '[]'::jsonb) from tails t),
    'freqs', (select coalesce(jsonb_agg(jsonb_build_object('r', f.j ->> 'routeKey', 't', f.j ->> 'tail', 'a', f.j ->> 'depHub',
                                                           'b', f.j ->> 'arrDest', 'c', f.j ->> 'depDest', 'd', f.j ->> 'arrHub',
                                                           'days', f.j ->> 'days', 'o', f.j ->> 'noOut', 'k', f.j ->> 'noBack',
                                                           'l', f.j ->> 'launched') order by f.id), '[]'::jsonb) from freqs f),
    -- signed interline agreements, in the order the old document's keys came in (jsonb: shorter keys first, then bytes)
    'interline', (select coalesce(jsonb_agg(jsonb_build_object('pair', x.pair, 'partner', x.partner, 'date', x.date)
                                            order by octet_length(x.pair), x.pair collate "C"), '[]'::jsonb)
                    from (select al.planner_name || '|' || i.country_code as pair, i.partner, i.decided_on::text as date
                            from w
                            join public.interline_agreements i on i.world_id = w.id
                            join public.airlines al on al.id = i.airline_id
                           where i.status = 'signed') x),
    'posts', (select coalesce(jsonb_agg(jsonb_build_object('slug', p.slug, 'at', p.published_at, 'title', p.title, 'summary', p.summary,
                                                           'body', p.body, 'tag', p.tag, 'airline', p.airline, 'image', p.image,
                                                           'credit', p.image_credit) order by p.published_at desc), '[]'::jsonb)
                from public.site_posts p),
    'reports', (select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'kind', r.kind, 'period', r.period, 'title', r.title,
                                                             'summary', case when r.kind = 'newsletter' then r.summary end,
                                                             'at', r.published_at, 'status', r.status, 'has_pdf', r.pdf_b64 is not null)
                                          order by coalesce(r.published_at, now() + interval '1 year') desc), '[]'::jsonb)
                  from public.site_reports r),
    -- site_content's keys (photos, logos ...; markets is the investors'), with mct from world_airports
    'content', coalesce((select jsonb_object_agg(c.key, c.value) from public.site_content c where c.key not in ('markets', 'mct')), '{}'::jsonb)
               || coalesce((select jsonb_build_object('mct', jsonb_object_agg(wa.airport_code, wa.mct_min))
                              from w join public.world_airports wa on wa.world_id = w.id
                             where wa.mct_min is not null
                            having count(*) > 0), '{}'::jsonb)
  );
$function$;

-- ============================================================ 2. site_investor()
create or replace function public.site_investor(p_password text)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
declare h text; w bigint; v_doc jsonb;
begin
  select r.pass_hash into h from public.report_access r limit 1;
  if h is null or p_password is null or extensions.crypt(p_password, h) <> h then return jsonb_build_object('ok', false); end if;
  select x.id into w from public.worlds x where x.is_default;
  -- cash and next-7-day costs exactly as the planner gets them (design §8): the capture's figure unless typed by hand
  v_doc := (public.planner_state_get(w) ->> 'json')::jsonb;
  return jsonb_build_object('ok', true, 'cash', v_doc -> 'cash', 'fixed7', v_doc -> 'fixed7',
    -- money spent, in the planner's order and millions; orders were logged without a kind
    'capex', (select coalesce(jsonb_agg(jsonb_build_object('date', s.spent_on::text, 'airline', al.planner_name,
                                                           'm', trim_scale(s.amount / 1000000),
                                                           'kind', case when s.kind <> 'order' then s.kind end) order by s.id), '[]'::jsonb)
                from public.spending_log s join public.airlines al on al.id = s.airline_id
               where s.world_id = w),
    'markets', (select c.value from public.site_content c where c.key = 'markets'),
    'reports', (select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'kind', r.kind, 'period', r.period, 'title', r.title,
                                                             'summary', r.summary, 'at', r.published_at, 'status', r.status,
                                                             'has_pdf', r.pdf_b64 is not null)
                                          order by coalesce(r.published_at, now() + interval '1 year') desc), '[]'::jsonb)
                  from public.site_reports r where r.kind <> 'newsletter'));
end
$function$;

-- ============================================================ 3. export_for_report()
create or replace function public.export_for_report(p_secret text, p_kind text, p_arg text default null)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
begin
  if not exists (select 1 from public.ingest_secret s where s.secret = p_secret) then raise exception 'not allowed'; end if;
  if p_kind = 'snapshots' then
    return (select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'taken_at', s.taken_at, 'week', s.week, 'status', s.status) order by s.id), '[]'::jsonb)
              from public.game_snapshots s);
  elsif p_kind = 'airlines' then
    return (select coalesce(jsonb_agg(jsonb_build_object('id', a.enterprise_id, 'name', a.name, 'flights', a.flights, 'n_weekly', a.n_weekly)), '[]'::jsonb)
              from public.game_snapshot_airlines a where a.snapshot_id = p_arg::bigint);
  elsif p_kind = 'airports' then
    return (select coalesce(jsonb_agg(jsonb_build_object('code', a.code, 'info', a.info, 'stations', a.stations, 'news', a.news)), '[]'::jsonb)
              from public.game_snapshot_airports a where a.snapshot_id = p_arg::bigint);
  elsif p_kind = 'planner' then
    -- today's two documents, built from the tables by the adapter's getters (design §8)
    return jsonb_build_object('state', (public.planner_state_get() ->> 'json')::jsonb,
                              'loads', (select coalesce(jsonb_object_agg(g.month, g.json::jsonb), '{}'::jsonb) from public.planner_loads_get() g));
  end if;
  raise exception 'unknown kind';
end
$function$;

-- ============================================================ 4. the route research into the tables
-- planner_data's DATA document ({routes, coords, utc, countries}) into countries, airports and routes, writing only the
-- rows that change, by the loader's rules (private.load_planner_places, private.load_planner_network). A part missing
-- from the document, or of the wrong kind, leaves its rows as they are.
create or replace function private.research_apply(p_world_id bigint, p_doc jsonb)
 returns jsonb
 language plpgsql
 set search_path to ''
as $function$
declare w bigint := p_world_id; d jsonb := p_doc; n int; v_out jsonb := '{}'::jsonb; v_held text[];
begin
  if jsonb_typeof(d) is distinct from 'object' then return v_out; end if;

  -- countries: added or renamed (none removed: airports, airlines and interline point at them)
  if jsonb_typeof(d -> 'countries') = 'object' then
    insert into public.countries as c (code, name)
    select e.key, e.value #>> '{}' from jsonb_each(d -> 'countries') e where jsonb_typeof(e.value) = 'string'
    on conflict (code) do update set name = excluded.name where c.name is distinct from excluded.name;
    get diagnostics n = row_count; v_out := v_out || jsonb_build_object('countries', n);
  end if;

  -- airports: city, country and position from coords (none removed: the tables point at them)
  if jsonb_typeof(d -> 'coords') = 'object' then
    with src as (
      select e.key as code, e.value ->> 2 as city, e.value ->> 3 as cc,
             private.json_num(e.value -> 0) as lat, private.json_num(e.value -> 1) as lon
        from jsonb_each(d -> 'coords') e where jsonb_typeof(e.value) = 'array' and e.key <> '')
    insert into public.airports as a (code, city, country_code, lat, lon)
    select src.code, src.city, (select x.code from public.countries x where x.code = src.cc),
           case when abs(src.lat) <= 90 then round(src.lat, 5) end, case when abs(src.lon) <= 180 then round(src.lon, 5) end
      from src
    on conflict (code) do update set city = excluded.city, country_code = excluded.country_code, lat = excluded.lat, lon = excluded.lon
    where (a.city, a.country_code, a.lat, a.lon) is distinct from (excluded.city, excluded.country_code, excluded.lat, excluded.lon);
    get diagnostics n = row_count; v_out := v_out || jsonb_build_object('airports', n);
  end if;

  -- airports: UTC offsets. Flights and plan-card legs are stored in UTC, worked out with the offset they were typed
  -- under, so a new offset for an airport they use (without the world's own correction) would move them on screen.
  -- Design §4: the game is right and the legs are re-timed in a one-off fix, so such an offset is held back and named.
  if jsonb_typeof(d -> 'utc') = 'object' then
    if to_regclass('pg_temp.t_research_utc') is null then
      create temporary table t_research_utc (code text primary key, off numeric(4,2)) on commit drop;
    end if;
    truncate pg_temp.t_research_utc;
    -- the offset as private.json_num() reads it (a number, or digits in a string), worked out in line for speed
    insert into pg_temp.t_research_utc (code, off)
    select e.key, case when abs(n.off) <= 14 then round(n.off, 2) end
      from jsonb_each(d -> 'utc') e
      cross join lateral (
        select case jsonb_typeof(e.value) when 'number' then (e.value #>> '{}')::numeric
                 when 'string' then case when (e.value #>> '{}') ~ '^\s*-?\d+(\.\d+)?\s*$' then btrim(e.value #>> '{}')::numeric end end as off) n
     where e.key <> '';
    with changed as materialized (
      select u.code from pg_temp.t_research_utc u join public.airports a on a.code = u.code
       where a.utc_offset is distinct from u.off)
    select array_agg(c.code order by c.code) into v_held
      from changed c
     where exists (select 1 from public.flight_legs l
                    where (l.origin_code = c.code or l.dest_code = c.code)
                      and not exists (select 1 from public.world_airports x where x.world_id = l.world_id and x.airport_code = c.code
                                                                             and x.utc_offset_override is not null))
        or exists (select 1 from public.plan_card_legs l
                    where (l.origin_code = c.code or l.dest_code = c.code)
                      and not exists (select 1 from public.world_airports x where x.world_id = l.world_id and x.airport_code = c.code
                                                                             and x.utc_offset_override is not null));
    insert into public.airports as a (code, utc_offset)
    select u.code, u.off from pg_temp.t_research_utc u where u.code <> all (coalesce(v_held, '{}'))
    on conflict (code) do update set utc_offset = excluded.utc_offset where a.utc_offset is distinct from excluded.utc_offset;
    get diagnostics n = row_count;
    v_out := v_out || jsonb_build_object('utc offsets', n, 'utc offsets held back', to_jsonb(coalesce(v_held, '{}')));
  end if;

  -- routes: the research's own figures on research routes (a route added in the planner keeps its own, and the
  -- planner's overrides are never touched); a research route the research no longer lists goes, unless it carries an
  -- edit or a cabin, or a frequency, fare plan or flown flight points at it
  if jsonb_typeof(d -> 'routes') = 'array' then
    -- every airport a route names, by its code only, so no route is refused
    insert into public.airports (code)
    select distinct v ->> i from jsonb_array_elements(d -> 'routes') v, generate_series(1, 2) i
     where jsonb_typeof(v) = 'array' and (v ->> i) ~ '^[A-Z0-9]{3,4}$'
    on conflict (code) do nothing;
    if to_regclass('pg_temp.t_research_routes') is null then
      create temporary table t_research_routes (airline_id bigint, hub text, dest text, ord bigint, city text,
        country_label text, distance_km int, market text, stars smallint, primary key (airline_id, hub, dest)) on commit drop;
    end if;
    truncate pg_temp.t_research_routes;
    -- one entry per route: the first the research lists. Distance and stars are whole numbers, as private.json_int()
    -- reads them (a number, or digits in a string), worked out here in line: the function call per row took over a
    -- second for the 4,400 routes
    insert into pg_temp.t_research_routes (airline_id, hub, dest, ord, city, country_label, distance_km, market, stars)
    select distinct on (al.id, e.v ->> 1, e.v ->> 2) al.id, e.v ->> 1, e.v ->> 2, e.ord, e.v ->> 3, e.v ->> 4,
           case when n.dist = trunc(n.dist) and abs(n.dist) < 2000000000 then n.dist::int end, e.v ->> 6,
           case when n.stars = trunc(n.stars) and abs(n.stars) < 32000 then n.stars::smallint end
      from jsonb_array_elements(d -> 'routes') with ordinality as e(v, ord)
      join public.airlines al on al.world_id = w and al.planner_name = e.v ->> 0
      cross join lateral (
        select case jsonb_typeof(e.v -> 5) when 'number' then (e.v ->> 5)::numeric
                 when 'string' then case when (e.v ->> 5) ~ '^\s*-?\d+(\.\d+)?\s*$' then btrim(e.v ->> 5)::numeric end end as dist,
               case jsonb_typeof(e.v -> 7) when 'number' then (e.v ->> 7)::numeric
                 when 'string' then case when (e.v ->> 7) ~ '^\s*-?\d+(\.\d+)?\s*$' then btrim(e.v ->> 7)::numeric end end as stars) n
     where jsonb_typeof(e.v) = 'array'
       and exists (select 1 from public.airports a where a.code = e.v ->> 1)
       and exists (select 1 from public.airports a where a.code = e.v ->> 2)
     order by al.id, e.v ->> 1, e.v ->> 2, e.ord;
    insert into public.routes as x (world_id, airline_id, hub_code, dest_code, city, country_label, distance_km, market_id, stars, source)
    select w, r.airline_id, r.hub, r.dest, r.city, r.country_label, r.distance_km,
           (select m.id from public.markets m where m.airline_id = r.airline_id and m.name = r.market),
           r.stars, 'research'
      from pg_temp.t_research_routes r order by r.ord
    on conflict (airline_id, hub_code, dest_code) do update set city = excluded.city, country_label = excluded.country_label,
      distance_km = excluded.distance_km, market_id = excluded.market_id, stars = excluded.stars
    where x.source = 'research'
      and (x.city, x.country_label, x.distance_km, x.market_id, x.stars)
          is distinct from (excluded.city, excluded.country_label, excluded.distance_km, excluded.market_id, excluded.stars);
    get diagnostics n = row_count; v_out := v_out || jsonb_build_object('routes', n);
    delete from public.routes x
     where x.world_id = w and x.source = 'research'
       and not exists (select 1 from pg_temp.t_research_routes r where r.airline_id = x.airline_id and r.hub = x.hub_code and r.dest = x.dest_code)
       and not x.removed and x.removed_note is null and x.city_override is null and x.distance_override_km is null
       and x.market_override_id is null and not x.market_cleared and x.stars_override is null and not x.edit_kept
       and x.cabin_choice is null
       and not exists (select 1 from public.rotations o where o.route_id = x.id)
       and not exists (select 1 from public.fare_plan o where o.route_id = x.id)
       and not exists (select 1 from public.game_flights o where o.route_id = x.id);
    get diagnostics n = row_count; v_out := v_out || jsonb_build_object('routes removed', n);
  end if;
  return v_out;
end
$function$;

create or replace function public.planner_data_set(p_secret text, p_key text, p_value jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare w bigint; v_tables jsonb;
  v_actor text := current_setting('equinox.actor', true); v_detail text := current_setting('equinox.actor_detail', true);
begin
  if not exists (select 1 from public.ingest_secret s where s.secret = p_secret) then raise exception 'not allowed'; end if;
  -- the old planner reads its route research from here until #18
  insert into public.planner_data as x (key, value) values (p_key, p_value)
  on conflict (key) do update set value = excluded.value, updated_at = now();
  if p_key = 'DATA' then
    -- the change log names the script, unless the caller named itself (design §6)
    perform set_config('equinox.actor', coalesce(nullif(v_actor, ''), 'script'), true),
            set_config('equinox.actor_detail', coalesce(nullif(v_detail, ''), 'planner_data_set'), true);
    select x.id into w from public.worlds x where x.is_default;
    v_tables := private.research_apply(w, p_value);
    perform set_config('equinox.actor', coalesce(v_actor, ''), true), set_config('equinox.actor_detail', coalesce(v_detail, ''), true);
  end if;
  return jsonb_build_object('ok', true, 'bytes', length(p_value::text))
         || case when v_tables is null then '{}'::jsonb else jsonb_build_object('tables', v_tables) end;
end
$function$;

-- ============================================================ 5. connection times
-- A world's minimum connection times from a whole map {airport code: minutes}, as site_admin('content', 'mct') is sent
-- it: each airport's mct_min set, and the times of airports the map no longer lists cleared (a row nothing else
-- describes then goes, as the adapter tidies). Refuses a map that isn't airport codes with whole minutes, 0 to 1440.
create or replace function private.world_mct_set(p_world_id bigint, p_mct jsonb)
 returns jsonb
 language plpgsql
 set search_path to ''
as $function$
declare bad text; n_set int; n_cleared int; n_gone int; v_cleared text[];
begin
  if jsonb_typeof(p_mct) is distinct from 'object' then
    raise exception 'mct must be an object of airport code: minutes' using errcode = '22023';
  end if;
  select string_agg(e.key, ', ' order by e.key) into bad from jsonb_each(p_mct) e
   where e.key !~ '^[A-Z0-9]{3,4}$' or private.json_int(e.value) is null or private.json_int(e.value) not between 0 and 1440;
  if bad is not null then
    raise exception 'mct: not an airport code with whole minutes (0 to 1440): %', bad using errcode = '22023';
  end if;
  insert into public.airports (code) select e.key from jsonb_each(p_mct) e on conflict (code) do nothing;
  insert into public.world_airports as x (world_id, airport_code, mct_min)
  select p_world_id, e.key, private.json_int(e.value)::smallint from jsonb_each(p_mct) e
  on conflict (world_id, airport_code) do update set mct_min = excluded.mct_min where x.mct_min is distinct from excluded.mct_min;
  get diagnostics n_set = row_count;
  with c as (
    update public.world_airports x set mct_min = null
     where x.world_id = p_world_id and x.mct_min is not null and not (p_mct ? x.airport_code)
    returning x.airport_code)
  select array_agg(c.airport_code), count(*) into v_cleared, n_cleared from c;
  delete from public.world_airports x
   where x.world_id = p_world_id and x.airport_code = any (coalesce(v_cleared, '{}'))
     and x.mct_min is null and x.night_ban_from is null and x.night_ban_to is null and x.utc_offset_override is null
     and x.game_airport_id is null and not x.closed and x.note is null
     and not exists (select 1 from public.airline_bases b where b.world_id = p_world_id and b.airport_code = x.airport_code);
  get diagnostics n_gone = row_count;
  return jsonb_build_object('set', n_set, 'cleared', n_cleared, 'removed', n_gone);
end
$function$;

create or replace function public.site_admin(p_secret text, p_kind text, p_payload jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_actor text := current_setting('equinox.actor', true); v_detail text := current_setting('equinox.actor_detail', true);
begin
  if not exists (select 1 from public.ingest_secret s where s.secret = p_secret) then raise exception 'not allowed'; end if;
  if p_kind = 'post' then
    insert into public.site_posts as x (slug, published_at, title, summary, body, tag, airline, image, image_credit, auto)
    values (p_payload->>'slug', coalesce((p_payload->>'at')::timestamptz, now()), p_payload->>'title', p_payload->>'summary', p_payload->>'body',
            p_payload->>'tag', p_payload->>'airline', p_payload->>'image', p_payload->>'credit', coalesce((p_payload->>'auto')::boolean, false))
    on conflict (slug) do update set published_at = excluded.published_at, title = excluded.title, summary = excluded.summary, body = excluded.body,
      tag = excluded.tag, airline = excluded.airline, image = excluded.image, image_credit = excluded.image_credit;
  elsif p_kind = 'report' then
    insert into public.site_reports as x (kind, period, title, summary, published_at, status, pdf_b64)
    values (p_payload->>'kind', p_payload->>'period', p_payload->>'title', p_payload->>'summary', (p_payload->>'at')::timestamptz,
            coalesce(p_payload->>'status', 'published'), p_payload->>'pdf')
    on conflict (kind, period) do update set title = excluded.title, summary = excluded.summary, published_at = excluded.published_at,
      status = excluded.status, pdf_b64 = coalesce(excluded.pdf_b64, x.pdf_b64);
  elsif p_kind = 'content' then
    if p_payload->>'key' = 'mct' then
      -- connection times live in world_airports (design §2), which site_public() reads; the change log names the script,
      -- unless the caller named itself (design §6)
      perform set_config('equinox.actor', coalesce(nullif(v_actor, ''), 'script'), true),
              set_config('equinox.actor_detail', coalesce(nullif(v_detail, ''), 'site_admin'), true);
      perform private.world_mct_set((select x.id from public.worlds x where x.is_default), p_payload->'value');
      perform set_config('equinox.actor', coalesce(v_actor, ''), true), set_config('equinox.actor_detail', coalesce(v_detail, ''), true);
    end if;
    -- kept for every key, mct included: until the switch-over the adapter falls back on site_content.mct for a hub
    insert into public.site_content as x (key, value) values (p_payload->>'key', p_payload->'value')
    on conflict (key) do update set value = excluded.value, updated_at = now();
  else raise exception 'unknown kind'; end if;
  return jsonb_build_object('ok', true);
end
$function$;

-- ============================================================ 6. Photos
create or replace function public.site_set_airline_logo(p_airline text, p_url text, p_path text default null)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare m jsonb;
begin
  if not public.is_planner_user() then raise exception 'not allowed'; end if;
  -- one of our airlines (by the planner's name for it) in the world the planner shows (#14), not a list in the code
  if not exists (select 1 from public.airlines a
                   join public.groups g on g.id = a.group_id and g.world_id = a.world_id
                   join public.worlds x on x.id = a.world_id and x.is_default
                  where a.planner_name = p_airline and g.kind = 'ours')
     or p_url is null or p_url !~ '^https://' then
    raise exception 'bad input';
  end if;
  select c.value into m from public.site_content c where c.key = 'media';
  m := coalesce(m, '{}'::jsonb);
  m := jsonb_set(m, '{logos}', coalesce(m->'logos', '{}'::jsonb), true);
  m := jsonb_set(m, array['logos', p_airline], jsonb_strip_nulls(jsonb_build_object('url', p_url, 'path', p_path, 'at', now())), true);
  insert into public.site_content as x (key, value) values ('media', m) on conflict (key) do update set value = excluded.value, updated_at = now();
  return jsonb_build_object('ok', true);
end
$function$;

-- ============================================================ 7. access (design §5)
-- The replaced public functions keep their grants (create or replace keeps them). The new internal ones are closed.
revoke all on function private.research_apply(bigint, jsonb), private.world_mct_set(bigint, jsonb) from public, anon, authenticated;

-- ============================================================ 8. descriptions (decision #10)
comment on function public.site_public() is 'Everything the public website shows, in one call: hubs and focus cities an airline flies from, aircraft flying, the week''s frequencies (local times), signed interlines, posts, the reports list, site_content (photos, logos) and the minimum connection times (content.mct), built from the tables (#13, pull request 8), plus our airlines (names, codes, colours, the website''s text, display order) from airlines. Same answer as before #13, apart from airlines and updated_at (when the planner''s data last changed). No bank or transfer times, cabin layouts or aircraft on order (6 Oct). Anyone may call it; runs as owner.';
comment on function public.site_investor(text) is 'The investor page''s data, when the password matches report_access: cash and next-7-day costs as planner_state_get() gives them (the capture''s figure unless typed by hand), money spent from spending_log, markets from site_content, and the investor reports list. Runs as owner.';
comment on function public.export_for_report(text, text, text) is 'Exports for the weekly report and gander monthly: world-scan snapshots, a scan''s airlines and airports, and the planner ({state, loads}: today''s planner_state and planner_loads documents, built from the tables by planner_state_get() and planner_loads_get()). Needs the ingest secret.';
comment on function public.planner_data_set(text, text, jsonb) is 'Replaces one planner_data entry (the old planner reads its route research there until #18). For the research (key DATA) it also writes countries, airports and routes, only the rows that change (private.research_apply(); change log actor script unless the caller named itself), and answers what changed under tables. Needs the ingest secret.';
comment on function public.site_admin(text, text, jsonb) is 'Publishes website content: newsroom posts, reports and site content. Content mct (minimum connection times, {airport code: minutes}) also sets world_airports, which site_public() reads (private.world_mct_set(); change log actor script unless the caller named itself); site_content.mct is kept too, for the adapter until the switch-over. Needs the ingest secret.';
comment on function public.site_set_airline_logo(text, text, text) is 'The planner''s Photos screen: sets an airline''s logo after the upload, for one of our airlines in airlines (by the planner''s name for it). Staff only.';
comment on function private.research_apply(bigint, jsonb) is 'planner_data_set()''s step for the route research (planner_data DATA: routes, coords, utc, countries): writes countries, airports and a world''s research routes, only the rows that change, by the loader''s rules. Added routes and the planner''s overrides are never touched; a research route no longer listed goes unless something points at it or it carries an edit. A new UTC offset for an airport that flights or plan-card legs use (with no world correction) is held back and named, since their UTC times were worked out with the old one (design §4). A part missing from the document leaves its rows alone. Returns how many rows each part changed.';
comment on function private.world_mct_set(bigint, jsonb) is 'site_admin()''s step for content mct: a world''s minimum connection times from the whole map {airport code: minutes}, into world_airports.mct_min; times of airports the map no longer lists are cleared, and a row nothing else describes goes. Refuses anything but airport codes with whole minutes, 0 to 1440. Returns how many were set, cleared and removed.';

comment on table public.planner_state is 'The whole planner in one JSON row (id main): plan cards, to-dos, aircraft, frequencies, deliveries, the fare plan, interline and reference data. Written by the planner on every change, and by Claude for data-only changes. Read by the planner, and by the adapter (side by side and the loader) until the switch-over freezes it (#13, pull request 9). The website and scripts read the tables instead (pull request 8).';
comment on table public.planner_loads is 'Daily loads as the planner keeps them, one JSON document per month. Written only by save_loads() (the planner) and apply_loads_from_capture() (after each loads capture), both of which merge days rather than replace the month. Read by the planner, and by the adapter until the switch-over freezes it (#13, pull request 9); export_for_report() reads planner_loads_get() instead (pull request 8).';
comment on table public.planner_data is 'The route research the planner is built on, in one row (key DATA): routes, airport coordinates, UTC offsets and countries. Written by planner_data_set(), which also writes countries, airports and routes. Read by the planner when it opens (until #18), the adapter and export_planner_data().';
comment on table public.site_content is 'Website content kept as data, one row per key: media (destination photos and airline logos), markets, and mct (minimum connection times, also used by the schedule optimiser; since #13''s pull request 8 site_admin() writes them to world_airports too, and site_public() reads them from there, so this copy is kept only for the adapter until the switch-over). Written by site_admin() and the planner''s Photos screen. Read by site_public() and site_investor().';
comment on table public.world_airports is 'What a world says about an airport, only where there is something to say: minimum connection time, night ban, a corrected UTC offset, closure. An airport''s offset in a world is coalesce(utc_offset_override, airports.utc_offset). Replaces site_content.mct, ref.hubs[].mct, ref.curfews and ref.utcOverrides. Connection times are written by the planner (a hub''s) and by site_admin() (the whole map), and read by site_public() as content.mct.';
comment on table public.airports is 'Every airport in the route research: city, country, position and UTC offset as the game gives them, the same in every world (a world''s own corrections are in world_airports). Loaded from planner_data.coords and planner_data.utc, plus code-only rows for any other airport the planner names (#13, pull request 4); kept in step with the research by planner_data_set() since pull request 8.';
comment on table public.countries is 'Country names by ISO code (-- for unknown). The same in every world. Replaces planner_data.countries; kept in step with the research by planner_data_set().';
comment on table public.routes is 'Every route an airline could fly, has added or has removed: the route research and the routes added in the planner, with the planner''s overrides (null = the research value; research refreshes never touch them). Replaces planner_data.routes, routesAdded, routeEdits and routeCabin. The research''s own figures are kept in step by planner_data_set().';
comment on table public.airlines is 'Every airline we track in a world: our own, and from #13''s capture work the rivals the world scan sees (their columns about our airlines stay null). Game ID, codes, home airport, colours and the website''s text, which today are copied in the planner (CODE_AL, CAP_HOME, AIRLINE_ORDER, LIVERY) and the capture. The website reads them from site_public().airlines (its own copy is only a fallback), and the Photos screen checks airlines against them. The game link is worked out from worlds.game_host and game_id.';
comment on table public.spending_log is 'Money spent, in AS$: aircraft orders, cabins and refits, losses. Replaces the planner''s capex. Read by site_investor().';

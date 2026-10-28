-- Competition analysis (manual §3, market share first; migration 20261021235000_competition.sql; spec
-- docs/specs/2026-10-21-competition-analysis.md §1). Run by database/rehearse.sh on the copy of last night's backup, after
-- the new migrations, inside a transaction that is rolled back. A failed check stops with an error that says which (codes,
-- counts and words of the hand-made world only). Everything is made in a world of its own, so nothing on the copy is
-- touched or counted; the copy's own numbers are printed at the end (counts only).
--   The world: two of our airlines and three rivals. C1 (main hub YA1, hub YA2, focus YA3) flies YA1–YB2 and YA1–YB3,
--   each daily both ways (14 a week each, 14 from its main hub); C2 (main hub YB1, focus YB4) flies YB4–YA1. Three finished
--   scans: s1 1 Feb, s2 8 Feb, s3 12 Feb (08:00 UTC), and one still running on 13 Feb. The moment T is 13 Feb 12:00, so
--   latest s3, week before s1 (s2 is only 4 days before s3), previous s2.
--     Rival One: YA1–YC1 7 and YA1–YC2 14 in every scan, and starts on YA1–YB2 in s3 (7): a threat from 12 Feb.
--     Rival Two: YA1–YB3 7 in s1, 14 from s2 (added 7: a threat from 8 Feb), YC2–YA1 7, and YA2→YC9 21 a week (over 2 a
--       day from C1's hub YA2 to YC9: that route is contested).
--     Rival Three: YB3–YA1 3 in s1 and s2, 6 in s3 (3 added, under the 7: no threat); 300 departures a week at YA3 in s3
--       (C1's focus city YA3 is contested).
--     Cargo Four, freighters only (the weekly report's rule: a type ending in F, 74Y, or none): from s3 on YA1–YB2 (a
--       77F), YA1–YB3 (a 74Y), YA1–YC1 (no type) and YA2–YC9; never a rival anywhere (market share, group line, threats,
--       openings, profiles), though its totals say 999 a week.
--   The test's own types, as the default line (manual §3): E195 146 seats 3,542 km, E190 114 4,065, A320 SHARP 189 3,355,
--   A320 Heavy 189 4,708, A321 LIGHT 240 4,192, A321XLR 240 6,939, A350-900 440, A350-1000 480; C1 may buy all, C2 every
--   narrowbody (as Ryanair: no A350).
--   C1's list (markets M1 and M2, and one route with none): YA1–YC1 5★ 1,000 km, YA1–YC2 5★ 2,000, YA1–YC3 4★ 3,000,
--   YA1–YC4 4★ 3,800, YA1–YC5 2★ 5,000, YA1–YC6 3★ 12,000, YA1–YC7 3★ 16,000, YA2–YC8 5★ 1,500, YA2–YC9 3★ 1,500, YA3–YCA
--   3★ 1,500 (no market), YA1–YB4 (C2 flies it: no opening), YA1–YCZ (removed: not on the list). C2's: YB1–YD1 3★ 1,000
--   and YB1–YD9 3★ 8,000 (beyond every type C2 may buy: left out).
--   1. The setting competition_threat_min_weekly 7 in every world, described; who may call competition() (signed in only,
--      stable, as owner with an empty search path, described) and its builders (internal).
--   2. The scans used, with their dates; the group line from the scans' totals.
--   3. Market share by market, with its change against the week-before scan: ours from the live legs now and from the
--      week-before scan then, the rivals' on the same pairs, our share, the top rivals; our other airline isn't a rival.
--   4. Threats: one appearing with s3 (started), one from s2 (added 7), none for 3 added; each leaves 7 days after its scan.
--   5. Openings ranked (stars, rivals' departures, distance, code; not allowed after, marked with the reason), the hubs-first
--      marks (main hub, contested route, contested base, not contested), the variant by stars and by reach (E190 past the
--      E195's reach; the XLR for reach on a 2-star city; the A350-900 at 12,000 km, the -1000 at 16,000), p_limit, and one left
--      out beyond every type's reach (C2). Hubs first open once the main hub is at its target.
--   6. Rival profiles: by pairs shared, then their departures on them; each one's size, change, airports and biggest airports.
--   7. One scan, and none: no comparison, no threats, nothing contested; signed out and an account that isn't staff are
--      refused; staff get what postgres gets.
--   8. November's trunks (manual §4; trunk_month_from and trunk_month_to, 1 to 30 Nov 2026, in every world, described):
--      on 10 Nov 2026 the trunks (pairs between two of our bases, any airline's) come first, shortest first, allowed
--      (hubs first suspended), a long one not left out for reach (C2 takes the world's A350); the other openings after as
--      always; on 31 Oct and 1 Dec nothing changes.
--   9. The A350 cut-over (migration 20261027220000; spec docs/specs/2026-10-27-competition-a350-cutover.md):
--      settings.a350_1000_from_km 14200 km in every world, described; an opening just under it (14,100 km) and at it
--      (14,200) on the A350-900, one just past it (14,300) on the -1000, wide_full_cabin_km the setting's; the setting
--      moved to 14,000 moves the cut-over with no code change, an airline's own row comes first, and with no row the
--      cut-over is 14,200. No opening has variant_alt or variant_note (the E190-E2 note went on 27 Oct).
--  10. The weekly report's three biggest competitors (migration 20261022040000; spec
--      docs/specs/2026-10-21-report-three-competitors.md §1): on C1's two pairs in s3, Rival Two (14), Rival One (7) and
--      Rival Three (6), each with its pairs, whole passenger network now and in s1, and the change; Cargo Four and C2 never;
--      self, C1 from the same scans. C2: no rival on its pair. Then Rival Five, new in s3 (no schedule in s1), 14 on both of
--      C1's pairs: the tie with Rival Two goes by name, Rival Three drops out as the fourth, and Rival Five has no
--      weekly_before or change. With one scan no week-before figures; with none, no competitors and no self. The export
--      (private.fig_export(), export_for_report('figures')) carries each airline's competitors, self and scans as
--      competition() gives them.
--   On the copy (section 2, before the hand-made world so the rehearsal prints it): each airline's counts and how long it
--   takes (under the 8 s staff limit), its A350 cut-over and how many of its openings are on the A350 beyond it (across
--   every opening), with none carrying variant_alt or variant_note, the group's share, the top 5 openings and the latest
--   scan's threats.

create temporary table t_cp (k text primary key, v jsonb) on commit drop;
grant select, insert, update on t_cp to authenticated, anon;
insert into public.planner_users (email) values ('competition-staff@example.com') on conflict do nothing;

-- ---------------------------------------------------------------- 1. the setting, and who may call competition()
do $test$
declare n_worlds int := (select count(*) from public.worlds); f text := 'public.competition(bigint, timestamptz, integer)'; g text;
begin
  assert (select count(*) from public.settings s where s.key = 'competition_threat_min_weekly' and s.airline_id is null and s.value = '7'::jsonb
            and s.unit = 'departures a week' and length(coalesce(s.description, '')) > 80 and s.since = date '2026-10-21' and s.reason is not null) = n_worlds,
    'competition_threat_min_weekly isn''t 7 in every world, described, since 21 Oct, with its reason';
  assert (select p.prosecdef and p.provolatile = 's' and coalesce('search_path=""' = any (p.proconfig), false) from pg_proc p where p.oid = f::regprocedure),
    f || ' isn''t stable, run as owner with an empty search path';
  assert not has_function_privilege('anon', f, 'execute'), 'signed out, ' || f || ' can be called';
  assert has_function_privilege('authenticated', f, 'execute'), 'signed in, ' || f || ' can''t be called';
  assert length(coalesce(obj_description(f::regprocedure, 'pg_proc'), '')) > 400, f || ' has no description';
  foreach g in array array['private.fig_competition(bigint, timestamptz, integer)', 'private.competition_threats(bigint, timestamptz)',
                           'private.scan_pair_flights(bigint[], text[])'] loop
    assert not has_function_privilege('authenticated', g, 'execute') and not has_function_privilege('anon', g, 'execute'), g || ' can be called from outside';
    assert (select not p.prosecdef and p.provolatile = 's' and coalesce('search_path=""' = any (p.proconfig), false) from pg_proc p where p.oid = g::regprocedure),
      g || ' runs as owner, isn''t stable or has no empty search path';
    assert length(coalesce(obj_description(g::regprocedure, 'pg_proc'), '')) > 60, g || ' has no description';
  end loop;
  -- the passenger rule: internal too, immutable, with an empty search path
  assert not has_function_privilege('authenticated', 'private.scan_passenger(text)', 'execute')
     and not has_function_privilege('anon', 'private.scan_passenger(text)', 'execute'), 'scan_passenger() can be called from outside';
  assert (select not p.prosecdef and p.provolatile = 'i' and coalesce('search_path=""' = any (p.proconfig), false) from pg_proc p
           where p.oid = 'private.scan_passenger(text)'::regprocedure),
    'scan_passenger() runs as owner, isn''t immutable or has no empty search path';
  assert length(coalesce(obj_description('private.scan_passenger(text)'::regprocedure, 'pg_proc'), '')) > 60, 'scan_passenger() has no description';
  assert (select string_agg(coalesce(t, 'null') || ' ' || private.scan_passenger(t), ', ' order by o)
            from unnest(array['320', '77W', '73G', '77F', '76F', 'ATF', 'ABX', '74Y', '77X', '76X', '', null]) with ordinality as x(t, o))
         = '320 true, 77W true, 73G true, 77F false, 76F false, ATF false, ABX false, 74Y false, 77X false, 76X false,  false, null false',
    'scan_passenger() isn''t the weekly report''s rule';
  raise notice 'competition_threat_min_weekly 7 in each of the % world(s), described; competition(): signed in only, stable, as owner with an empty search path, described; its three builders and the passenger rule internal', n_worlds;
end
$test$;

-- ---------------------------------------------------------------- 2. the copy (counts and codes only)
-- Each of our airlines' answer now, and how long it took (signed in, staff have 8 s); the pull request's numbers (spec
-- §Checks): the group's share, each airline's top 5 openings, and the threats the latest scan showed against the one before
-- it (read an hour after the latest scan, so they're in their 7 days whenever this runs); the types of the flights airlines
-- named Cargo fly on our pairs; and November's list (as of 10 Nov 2026: each airline's trunks and its first 5). Five
-- notices, first after the setting's, since the rehearsal prints a passing test's first six.
do $test$
declare r record; d jsonb; t0 timestamptz; ms int; worst int := 0; w bigint := (select id from public.worlds where is_default);
  v_scan timestamptz := (select max(s.taken_at) from public.game_scans s where s.world_id = (select id from public.worlds where is_default) and s.status = 'done');
  first_doc jsonb; th jsonb; counts text[] := '{}'; tops text[] := '{}'; threats text[] := '{}'; nov text[] := '{}'; dn jsonb;
  wide text[] := '{}'; v_wide text; v_alt int;
begin
  for r in select al.airline_id, al.iata_code from private.fig_airlines(w) al order by al.ord loop
    t0 := clock_timestamp();
    d := private.fig_competition(r.airline_id, now());
    ms := round(extract(epoch from clock_timestamp() - t0) * 1000);
    worst := greatest(worst, ms);
    first_doc := coalesce(first_doc, d);
    counts := counts || format('%s %s markets, %s threats, %s openings (%s allowed, %s left out), %s profiles, %s ms', r.iata_code,
      jsonb_array_length(d -> 'markets'), jsonb_array_length(d -> 'threats'), d ->> 'openings_count', d ->> 'openings_allowed',
      d ->> 'openings_left_out', jsonb_array_length(d -> 'profiles'), ms);
    -- the A350 cut-over (27 Oct): across every opening, untimed; no opening names an alternative any more
    select format('%s %s km, %s of %s openings on the A350 past it', r.iata_code, min(dd.d #>> '{settings,wide_full_cabin_km}'),
                  count(*) filter (where o #>> '{variant,size}' = 'wide' and (o ->> 'distance_km')::numeric > (dd.d #>> '{settings,wide_full_cabin_km}')::numeric),
                  count(o)),
           count(*) filter (where o ? 'variant_alt' or o ? 'variant_note')
      into v_wide, v_alt
      from (select private.fig_competition(r.airline_id, now(), 100000) as d) dd left join lateral jsonb_array_elements(dd.d -> 'openings') o on true;
    assert v_alt = 0, format('on the copy %s has %s openings with variant_alt or variant_note', r.iata_code, v_alt);
    wide := wide || v_wide;
    tops := tops || format('%s: %s', r.iata_code, coalesce((select string_agg(format('%s. %s %s* %s km %s/wk %s%s', o ->> 'rank', o ->> 'route', o ->> 'stars',
        o ->> 'distance_km', o ->> 'rivals_weekly', o #>> '{variant,type}', case when (o ->> 'allowed')::boolean then '' else ' (not yet)' end), ', ' order by (o ->> 'rank')::int)
      from jsonb_array_elements(d -> 'openings') o where (o ->> 'rank')::int <= 5), 'none'));
    if v_scan is not null then
      th := private.fig_competition(r.airline_id, v_scan + interval '1 hour', 0) -> 'threats';
      threats := threats || format('%s %s%s', r.iata_code, jsonb_array_length(th),
        coalesce(' (' || (select string_agg(t ->> 'words', '; ' order by i) from jsonb_array_elements(th) with ordinality e(t, i) where i <= 8)
                 || case when jsonb_array_length(th) > 8 then format('; +%s more', jsonb_array_length(th) - 8) else '' end || ')', ''));
    end if;
    -- November (manual §4): the trunks first, shortest first
    t0 := clock_timestamp();
    dn := private.fig_competition(r.airline_id, '2026-11-10 12:00+00'::timestamptz, 5);
    ms := round(extract(epoch from clock_timestamp() - t0) * 1000);
    worst := greatest(worst, ms);
    nov := nov || format('%s %s trunks of %s openings, %s ms: %s', r.iata_code, dn ->> 'openings_trunks', dn ->> 'openings_count', ms,
      coalesce((select string_agg(format('%s. %s%s %s km %s%s%s%s', o ->> 'rank', o ->> 'route', case when (o ->> 'trunk')::boolean then ' trunk' else '' end,
          o ->> 'distance_km', o #>> '{variant,type}', case when (o #>> '{variant,own}')::boolean is false then ' (not its own)' else '' end,
          case when (o ->> 'allowed')::boolean then '' else ' (not yet)' end,
          coalesce(' also ' || nullif((select string_agg(x, '+') from jsonb_array_elements_text(o -> 'other_lists') x), ''), '')), ', ' order by (o ->> 'rank')::int)
        from jsonb_array_elements(dn -> 'openings') o), 'none'));
  end loop;
  assert worst < 8000, format('competition() took %s ms for one airline on the copy: over the 8 s staff limit', worst);
  raise notice '%', format('on the copy: the scans %s against %s; our airlines %s of %s departures a week, %s%% (then %s of %s, %s%%); %s; the slowest %s ms (staff limit 8 s); the A350 cut-over (none with variant_alt): %s',
    coalesce(left(first_doc #>> '{scans,latest,taken_at}', 10), 'none'), coalesce(left(first_doc #>> '{scans,week_before,taken_at}', 10), 'none'),
    first_doc #>> '{group,ours}', first_doc #>> '{group,world}', first_doc #>> '{group,share}',
    first_doc #>> '{group,ours_before}', first_doc #>> '{group,world_before}', first_doc #>> '{group,share_before}', array_to_string(counts, '; '), worst,
    array_to_string(wide, '; '));
  raise notice '%', 'on the copy, the top 5 openings: ' || array_to_string(tops, ' | ');
  raise notice '%', format('on the copy, the threats with the latest scan (%s, against the one before): %s', coalesce(left(v_scan::text, 10), 'none'),
    coalesce(nullif(array_to_string(threats, ' | '), ''), 'none'));
  -- freighters (the weekly report's rule): the latest scan's flights on a pair one of ours flies, by airlines whose name
  -- says Cargo, each type with whether it counts (a passenger type) or not
  raise notice '%', 'on the copy, airlines named Cargo on our pairs in the latest scan, by type (counted as passenger or left out): ' || coalesce((
    with fp as materialized (select distinct least(q.hub_code, q.dest_code) as a, greatest(q.hub_code, q.dest_code) as b from private.fig_freqs(w) q where q.live)
    select string_agg(format('%s %s %s×%s', x.name, x.ty, x.n, case when x.pax then 'counted' else 'left out' end), '; ' order by x.name, x.ty)
      from (select coalesce(ra.public_name, ra.game_name) as name, coalesce(f ->> 7, '') as ty, private.scan_passenger(f ->> 7) as pax, count(*) as n
              from public.game_scans s
              join public.game_scan_schedules sc on sc.scan_id = s.id
              join public.airlines ra on ra.id = sc.airline_id
              cross join lateral jsonb_array_elements(case when jsonb_typeof(sc.flights) = 'array' then sc.flights else '[]'::jsonb end) f
             where s.world_id = w and s.taken_at = v_scan and s.status = 'done' and coalesce(ra.public_name, ra.game_name) ilike '%cargo%'
               and jsonb_typeof(f) = 'array'
               and exists (select 1 from fp where fp.a = least(f ->> 2, f ->> 3) and fp.b = greatest(f ->> 2, f ->> 3))
             group by 1, 2, 3) x), 'none');
  raise notice '%', 'on the copy in November (as of 10 Nov 2026), each airline''s trunks and its first 5 openings: ' || array_to_string(nov, ' | ');
end
$test$;

-- ---------------------------------------------------------------- the hand-made world
-- a route on an airline's list; flown, it gets a rotation launched 1 Jan, an aircraft and its two legs, daily both ways
create function pg_temp.cp_route(w bigint, al bigint, hub text, dest text, stars int, dist int, market bigint, flown boolean, ty bigint, k int)
returns bigint language plpgsql as $f$
declare r bigint; rot bigint; ac bigint;
begin
  insert into public.routes (world_id, airline_id, hub_code, dest_code, distance_km, stars, market_id, source)
  values (w, al, hub, dest, dist, stars, market, 'research') returning id into r;
  if flown then
    insert into public.rotations (world_id, airline_id, route_id, launched_on) values (w, al, r, date '2030-01-01') returning id into rot;
    insert into public.aircraft (world_id, airline_id, registration, aircraft_type_id, status, base_code, acquired)
    values (w, al, 'YC-' || k, ty, 'active', hub, 'new') returning id into ac;
    insert into public.flight_legs (world_id, airline_id, rotation_id, leg_no, flight_no, origin_code, dest_code, aircraft_id, days_utc, dep_utc_min, block_min) values
      (w, al, rot, 1, 7000 + k * 2, hub, dest, ac, '{1,2,3,4,5,6,7}', 600, 90),
      (w, al, rot, 2, 7001 + k * 2, dest, hub, ac, '{1,2,3,4,5,6,7}', 800, 90);
  end if;
  return r;
end
$f$;

-- a flight in a scan's schedule: [code, number, from, to, weekdays, departure, arrival, type, operator]
create function pg_temp.cp_fl(code text, no int, o text, d text, days text, ty text default '320') returns jsonb language sql immutable as $f$
  select jsonb_build_array(code, no, o, d, days, '08:00', '10:00', ty, '')
$f$;

do $setup$
declare
  dw bigint := (select id from public.worlds where is_default);
  w bigint; g bigint; gr bigint; c1 bigint; c2 bigint; r1 bigint; r2 bigint; r3 bigint; r4 bigint; m1 bigint; m2 bigint; t_e195 bigint; ty record; s bigint;
  x record; sc jsonb := '{}'::jsonb;
begin
  perform set_config('equinox.actor', 'claude', true), set_config('equinox.actor_detail', 'competition test', true);
  insert into public.airports (code, utc_offset)
  select c, 0 from unnest(array['YA1', 'YA2', 'YA3', 'YB1', 'YB2', 'YB3', 'YB4', 'YC1', 'YC2', 'YC3', 'YC4', 'YC5', 'YC6', 'YC7', 'YC8', 'YC9',
                                'YCA', 'YCZ', 'YD1', 'YD9', 'YZZ']) c
  on conflict (code) do update set utc_offset = excluded.utc_offset;
  insert into public.worlds (name, game_host, kind) values ('competition test', 'competition.test', 'exclusive') returning id into w;
  insert into public.settings (world_id, airline_id, key, value, unit, description)
  select w, null, s2.key, s2.value, s2.unit, s2.description from public.settings s2 where s2.world_id = dw and s2.airline_id is null;
  -- the house rules' thresholds as the manual has them (manual §3), whatever the copy holds
  update public.settings set value = v.v from (values ('hub_first_departures', '750'::jsonb), ('contested_rival_weekly', '250'::jsonb),
                                                      ('contested_rival_daily', '2'::jsonb), ('hub_first_exempt', 'false'::jsonb),
                                                      ('competition_threat_min_weekly', '7'::jsonb)) v(k, v)
   where world_id = w and airline_id is null and key = v.k;
  insert into public.groups (world_id, name, kind) values (w, 'ours', 'ours') returning id into g;
  insert into public.groups (world_id, name, kind) values (w, 'rivals', 'rival') returning id into gr;
  insert into public.airlines (world_id, group_id, game_id, planner_name, public_name, iata_code, home_airport_code, active, position)
  values (w, g, 990601, 'Comp One', 'Comp One', 'C1', 'YA1', true, 1) returning id into c1;
  insert into public.airlines (world_id, group_id, game_id, planner_name, public_name, iata_code, home_airport_code, active, position)
  values (w, g, 990602, 'Comp Two', 'Comp Two', 'C2', 'YB1', true, 2) returning id into c2;
  -- rivals: one in a rival group, one placed in no group yet (as the scan leaves a new airline), one in the rival group
  insert into public.airlines (world_id, group_id, game_id, game_name, active) values (w, gr, 990691, 'Rival One', true) returning id into r1;
  insert into public.airlines (world_id, group_id, game_id, game_name, active) values (w, null, 990692, 'Rival Two', true) returning id into r2;
  insert into public.airlines (world_id, group_id, game_id, game_name, active) values (w, gr, 990693, 'Rival Three', true) returning id into r3;
  insert into public.airlines (world_id, group_id, game_id, game_name, active) values (w, gr, 990694, 'Cargo Four', true) returning id into r4;
  insert into public.airline_bases (world_id, airline_id, airport_code, role, is_main, position) values
    (w, c1, 'YA1', 'hub', true, 1), (w, c1, 'YA2', 'hub', false, 2), (w, c1, 'YA3', 'focus', false, 3),
    (w, c2, 'YB1', 'hub', true, 1), (w, c2, 'YB4', 'focus', false, 2);
  for ty in select * from (values ('CT E195', 146, 3542, 1771000), ('CT E190', 114, 4065, 1683000), ('CT A320 SHARP', 189, 3355, 2058000),
                                  ('CT A320 Heavy', 189, 4708, 2241000), ('CT A321 LIGHT', 240, 4192, 2401000), ('CT A321XLR', 240, 6939, 2862000),
                                  ('CT A350-900', 440, 11102, 7005000), ('CT A350-1000', 480, 11102, 7854000)) v(name, seats, range_km, price) loop
    insert into public.aircraft_types (world_id, name, seats_max, range_km, price, cruise_kmh, min_turn_min)
    values (w, ty.name, ty.seats, ty.range_km, ty.price, 840, 60) returning id into s;
    insert into public.airline_aircraft_types (world_id, airline_id, aircraft_type_id) values (w, c1, s);
    if ty.seats < 300 then insert into public.airline_aircraft_types (world_id, airline_id, aircraft_type_id) values (w, c2, s); end if;
    if ty.name = 'CT E195' then t_e195 := s; end if;
  end loop;
  insert into public.markets (world_id, airline_id, name, layout) values (w, c1, 'M1 short', 'Leisure') returning id into m1;
  insert into public.markets (world_id, airline_id, name, layout) values (w, c1, 'M2 long', 'Comfort') returning id into m2;

  perform pg_temp.cp_route(w, c1, 'YA1', 'YB2', 4, 800, m1, true, t_e195, 1);
  perform pg_temp.cp_route(w, c1, 'YA1', 'YB3', 4, 900, m1, true, t_e195, 2);
  perform pg_temp.cp_route(w, c1, 'YA1', 'YC1', 5, 1000, m1, false, null, 0);
  perform pg_temp.cp_route(w, c1, 'YA1', 'YC2', 5, 2000, m1, false, null, 0);
  perform pg_temp.cp_route(w, c1, 'YA1', 'YC3', 4, 3000, m2, false, null, 0);
  perform pg_temp.cp_route(w, c1, 'YA1', 'YC4', 4, 3800, m2, false, null, 0);
  perform pg_temp.cp_route(w, c1, 'YA1', 'YC5', 2, 5000, m2, false, null, 0);
  perform pg_temp.cp_route(w, c1, 'YA1', 'YC6', 3, 12000, m2, false, null, 0);
  perform pg_temp.cp_route(w, c1, 'YA1', 'YC7', 3, 16000, m2, false, null, 0);
  perform pg_temp.cp_route(w, c1, 'YA2', 'YC8', 5, 1500, m2, false, null, 0);
  perform pg_temp.cp_route(w, c1, 'YA2', 'YC9', 3, 1500, m2, false, null, 0);
  perform pg_temp.cp_route(w, c1, 'YA3', 'YCA', 3, 1500, null, false, null, 0);
  perform pg_temp.cp_route(w, c1, 'YA1', 'YB4', 3, 1200, m2, false, null, 0);
  s := pg_temp.cp_route(w, c1, 'YA1', 'YCZ', 5, 900, m1, false, null, 0);
  update public.routes set removed = true where id = s;
  perform pg_temp.cp_route(w, c2, 'YB4', 'YA1', 3, 1200, null, true, t_e195, 3);
  perform pg_temp.cp_route(w, c2, 'YB1', 'YD1', 3, 1000, null, false, null, 0);
  perform pg_temp.cp_route(w, c2, 'YB1', 'YD9', 3, 8000, null, false, null, 0);

  -- the scans: each airline's schedule, its totals (the group line) and, in s3, the airport summaries
  for x in select * from (values
      ('s1', timestamptz '2030-02-01 08:00:00+00', 'done', 7, 3, 90, 180, 290),
      ('s2', timestamptz '2030-02-08 08:00:00+00', 'done', 14, 3, 95, 190, 295),
      ('s3', timestamptz '2030-02-12 08:00:00+00', 'done', 14, 6, 100, 200, 300),
      ('s4', timestamptz '2030-02-13 08:00:00+00', 'running', 14, 6, 100, 200, 300)) v(k, at, status, r2_yb3, r3_yb3, r1_n, r2_n, r3_n) loop
    insert into public.game_scans (world_id, taken_at, status) values (w, x.at, x.status) returning id into s;
    sc := sc || jsonb_build_object(x.k, s);
    insert into public.game_scan_schedules (scan_id, world_id, airline_id, flights) values
      (s, w, c1, jsonb_build_array(pg_temp.cp_fl('CA', 1, 'YA1', 'YB2', '1234567'), pg_temp.cp_fl('CA', 2, 'YB2', 'YA1', '1234567'),
                                   pg_temp.cp_fl('CA', 3, 'YA1', 'YB3', '1234567'))),
      (s, w, c2, jsonb_build_array(pg_temp.cp_fl('CB', 1, 'YB4', 'YA1', '1234567'))),
      (s, w, r1, jsonb_build_array(pg_temp.cp_fl('R1', 1, 'YA1', 'YC1', '1234567'), pg_temp.cp_fl('R1', 2, 'YA1', 'YC2', '1234567'),
                                   pg_temp.cp_fl('R1', 3, 'YC2', 'YA1', '1234567'))
                 || case when x.k in ('s3', 's4') then jsonb_build_array(pg_temp.cp_fl('R1', 4, 'YA1', 'YB2', '1234567'),
                                                                         -- a running scan's start is never read
                                                                         pg_temp.cp_fl('R1', 5, 'YB3', 'YA1', case when x.k = 's4' then '1234567' else '' end))
                         else '[]'::jsonb end),
      (s, w, r2, jsonb_build_array(pg_temp.cp_fl('R2', 1, 'YA1', 'YB3', '1234567'), pg_temp.cp_fl('R2', 3, 'YC2', 'YA1', '1234567'),
                                   pg_temp.cp_fl('R2', 4, 'YA2', 'YC9', '1234567'), pg_temp.cp_fl('R2', 5, 'YA2', 'YC9', '1234567'),
                                   pg_temp.cp_fl('R2', 6, 'YA2', 'YC9', '1234567'))
                 || case when x.r2_yb3 = 14 then jsonb_build_array(pg_temp.cp_fl('R2', 2, 'YA1', 'YB3', '1234567')) else '[]'::jsonb end),
      (s, w, r3, jsonb_build_array(pg_temp.cp_fl('R3', 1, 'YB3', 'YA1', '135'))
                 || case when x.r3_yb3 = 6 then jsonb_build_array(pg_temp.cp_fl('R3', 2, 'YB3', 'YA1', '246')) else '[]'::jsonb end
                 || jsonb_build_array(pg_temp.cp_fl('R3', 3, 'YA3', 'YZZ', '1234567'))),
      -- freighters only, from s3 (the weekly report's rule: 77F ends in F, 74Y is listed, no type is no passenger flight)
      (s, w, r4, case when x.k in ('s3', 's4') then jsonb_build_array(pg_temp.cp_fl('C4', 1, 'YA1', 'YB2', '1234567', '77F'),
                                                                       pg_temp.cp_fl('C4', 2, 'YA1', 'YB3', '1234567', '74Y'),
                                                                       pg_temp.cp_fl('C4', 3, 'YA1', 'YC1', '1234567', ''),
                                                                       pg_temp.cp_fl('C4', 4, 'YA2', 'YC9', '1234567', 'ABX'))
                      else '[]'::jsonb end);
    insert into public.game_scan_airlines (scan_id, world_id, enterprise_id, airline_id, name, n_flights, n_weekly, n_airports, position) values
      (s, w, 990694, r4, 'Cargo Four', 4, 999, 4, 6),
      (s, w, 990601, c1, 'Comp One', 3, 21, 3, 1), (s, w, 990602, c2, 'Comp Two', 1, 7, 2, 2),
      (s, w, 990691, r1, 'Rival One', 5, x.r1_n, 12, 3), (s, w, 990692, r2, 'Rival Two', 6, x.r2_n, 25, 4),
      (s, w, 990693, r3, 'Rival Three', 3, x.r3_n, 31, 5);
    if x.k = 's3' then
      insert into public.scan_airline_airports (scan_id, world_id, airline_id, airport_code, weekly_departures, destinations) values
        (s, w, r3, 'YA3', 300, 12), (s, w, r2, 'YZZ', 100, 9), (s, w, r2, 'YA2', 50, 4), (s, w, r2, 'YB3', 30, 2), (s, w, r2, 'YC2', 7, 1),
        (s, w, c1, 'YA1', 14, 2);
    end if;
  end loop;

  perform set_config('equinox.actor', '', true), set_config('equinox.actor_detail', '', true);
  insert into t_cp values ('w', to_jsonb(w)), ('c1', to_jsonb(c1)), ('c2', to_jsonb(c2)), ('scans', sc),
                          ('t', to_jsonb(timestamptz '2030-02-13 12:00:00+00'));
end
$setup$;

-- ---------------------------------------------------------------- 2. the scans used, and the group line
do $test$
declare c1 bigint := (select (v #>> '{}')::bigint from t_cp where k = 'c1'); t timestamptz := (select (v #>> '{}')::timestamptz from t_cp where k = 't');
  sc jsonb := (select v from t_cp where k = 'scans'); d jsonb;
begin
  d := private.fig_competition(c1, t);
  insert into t_cp values ('c1_doc', d);
  assert d #>> '{scans,latest,id}' = sc ->> 's3' and d #>> '{scans,latest,taken_at}' = '2030-02-12T08:00:00.000Z'
     and d #>> '{scans,week_before,id}' = sc ->> 's1' and d #>> '{scans,week_before,taken_at}' = '2030-02-01T08:00:00.000Z'
     and d #>> '{scans,previous,id}' = sc ->> 's2' and d #>> '{scans,previous,taken_at}' = '2030-02-08T08:00:00.000Z',
    'the scans aren''t latest s3 (12 Feb), week before s1 (1 Feb: s2 is only 4 days before s3), previous s2: ' || (d -> 'scans')::text;
  -- from each airline's schedule, passenger flights only: s3 C1 21, C2 7, Rival One 28, Two 42, Three 13 (Cargo Four's
  -- freighters, and every scan total, n_weekly, left out); s1 21, 7, 21, 35, 10
  assert d -> 'group' = '{"ours": 28, "world": 111, "share": 25.2, "ours_before": 28, "world_before": 94, "share_before": 29.8, "ours_change": 0, "world_change": 17, "share_change": -4.6}'::jsonb,
    'the group line isn''t ours 28 of 111 passenger departures (25.2%) against 28 of 94 (29.8%): ' || (d -> 'group')::text;
  raise notice 'the scans: latest 12 Feb, week before 1 Feb (not 8 Feb, under 6 days before), previous 8 Feb, a running scan of 13 Feb left out; the group line from the schedules'' passenger flights, 28 of 111 a week (25.2%%) against 28 of 94 (29.8%%), freighters and the scans'' totals left out';
end
$test$;

-- ---------------------------------------------------------------- 3. market share, by market
do $test$
declare d jsonb := (select v from t_cp where k = 'c1_doc'); m jsonb; got text;
begin
  assert (select string_agg(x ->> 'name', ', ' order by i) from jsonb_array_elements(d -> 'markets') with ordinality e(x, i)) = 'M1 short, M2 long, No market',
    'the markets aren''t M1, M2 and No market, biggest first: ' || (d -> 'markets')::text;
  m := d -> 'markets' -> 0;
  assert m ->> 'pairs' = '4' and m ->> 'flown' = '2' and m ->> 'ours' = '28' and m ->> 'ours_before' = '21' and m ->> 'ours_change' = '7'
     and m ->> 'rivals' = '55' and m ->> 'rivals_before' = '38' and m ->> 'total' = '83'
     and (m ->> 'share')::numeric = 33.7 and (m ->> 'share_before')::numeric = 35.6 and (m ->> 'share_change')::numeric = -1.9,
    'M1 isn''t 4 pairs (2 flown, the removed one left out), ours 28 (21 a week before), rivals 55 (38), share 33.7% (35.6%, −1.9): ' || m::text;
  select string_agg(x ->> 'name' || ' ' || (x ->> 'weekly') || ' (' || (x ->> 'weekly_before') || ', ' || (x ->> 'change') || ') ' || (x ->> 'share') || '%', '; ' order by i)
    into got from jsonb_array_elements(m -> 'top') with ordinality e(x, i);
  assert got = 'Rival One 28 (21, 7) 33.7%; Rival Two 21 (14, 7) 25.3%; Rival Three 6 (3, 3) 7.2%', 'M1''s top rivals are ' || got;
  -- our other airline flies YA1–YB4 (M2): never a rival; M2's rivals are Rival Two's 21 from YA2 to YC9
  m := d -> 'markets' -> 1;
  assert m ->> 'ours' = '0' and m ->> 'rivals' = '21' and m ->> 'rivals_before' = '21' and (m ->> 'share')::numeric = 0 and m ->> 'pairs' = '8'
     and (select string_agg(x ->> 'name', ',') from jsonb_array_elements(m -> 'top') x) = 'Rival Two',
    'M2 isn''t 8 pairs with only Rival Two''s 21 (our other airline counted as a rival?): ' || m::text;
  m := d -> 'markets' -> 2;
  assert m ->> 'market_id' is null and m ->> 'pairs' = '1' and m ->> 'total' = '0' and m ->> 'share' is null,
    'the route with no market isn''t under No market with nothing flown: ' || m::text;
  raise notice 'market share: M1 ours 28 (21 in the week-before scan, +7) against rivals'' 55 (38): 33.7%% (35.6%%, −1.9), top Rival One 28, Rival Two 21, Rival Three 6; M2 0%% (our other airline not a rival); a route with no market under No market';
end
$test$;

-- ---------------------------------------------------------------- 4. threats: appearing, and leaving after 7 days
do $test$
declare c1 bigint := (select (v #>> '{}')::bigint from t_cp where k = 'c1'); t timestamptz := (select (v #>> '{}')::timestamptz from t_cp where k = 't');
  sc jsonb := (select v from t_cp where k = 'scans'); d jsonb := (select v from t_cp where k = 'c1_doc'); got text;
begin
  select string_agg(x ->> 'rival' || ' ' || (x ->> 'route') || ' ' || (x ->> 'kind') || ' ' || (x ->> 'then') || '>' || (x ->> 'now') || ' ours ' || (x ->> 'ours')
                    || ' on ' || left(x ->> 'on', 10) || ' until ' || left(x ->> 'until', 10) || case when (x ->> 'latest')::boolean then ' latest' else '' end, '; ' order by i)
    into got from jsonb_array_elements(d -> 'threats') with ordinality e(x, i);
  assert got = 'Rival One YA1–YB2 started 0>7 ours 14 on 2030-02-12 until 2030-02-19 latest; Rival Two YA1–YB3 added 7>14 ours 14 on 2030-02-08 until 2030-02-15',
    'the threats at 13 Feb are ' || coalesce(got, 'none');
  assert (select x ->> 'words' from jsonb_array_elements(d -> 'threats') x where x ->> 'rival' = 'Rival One') = 'Rival One started on YA1–YB2, 7 a week'
     and (select x ->> 'words' from jsonb_array_elements(d -> 'threats') x where x ->> 'rival' = 'Rival Two') = 'Rival Two added on YA1–YB3, 7 → 14 a week',
    'the threats'' words aren''t "Rival One started on YA1–YB2, 7 a week" and "Rival Two added on YA1–YB3, 7 → 14 a week": ' || (d -> 'threats')::text;
  -- before s3 (12 Feb 07:00): only Rival Two's, from s2
  d := private.fig_competition(c1, timestamptz '2030-02-12 07:00:00+00');
  assert (select string_agg(x ->> 'rival' || ' ' || (x ->> 'kind'), ', ') from jsonb_array_elements(d -> 'threats') x) = 'Rival Two added'
     and d #>> '{scans,latest,id}' = sc ->> 's2',
    'before 12 Feb the threats aren''t Rival Two''s alone, with s2 the latest: ' || (d -> 'threats')::text;
  -- 15 Feb 09:00, 7 days and an hour after s2: Rival Two's has left, Rival One's stays
  d := private.fig_competition(c1, timestamptz '2030-02-15 09:00:00+00');
  assert (select string_agg(x ->> 'rival' || ' ' || (x ->> 'kind'), ', ') from jsonb_array_elements(d -> 'threats') x) = 'Rival One started',
    'on 15 Feb the threats aren''t Rival One''s alone: ' || (d -> 'threats')::text;
  -- 19 Feb 09:00: none
  d := private.fig_competition(c1, timestamptz '2030-02-19 09:00:00+00');
  assert jsonb_array_length(d -> 'threats') = 0, 'on 19 Feb a threat is still listed: ' || (d -> 'threats')::text;
  raise notice 'threats: Rival One started on YA1–YB2 with the 12 Feb scan (7 a week), Rival Two added 7 on YA1–YB3 with the 8 Feb scan (7 → 14), Rival Three''s 3 more none; on 12 Feb at 07:00 only Rival Two''s; on 15 Feb Rival Two''s has left (7 days); on 19 Feb none';
end
$test$;

-- ---------------------------------------------------------------- 4b. freighters are no one's rivals
do $test$
declare d jsonb := (select v from t_cp where k = 'c1_doc');
begin
  assert d::text not like '%Cargo Four%', 'Cargo Four (freighters only) shows up in competition(): ' || d::text;
  assert not exists (select 1 from private.competition_threats((select (v #>> '{}')::bigint from t_cp where k = 'c1'), (select (v #>> '{}')::timestamptz from t_cp where k = 't')) t
                      where t.rival = 'Cargo Four'), 'a freighter is a threat (it would pause the fare ladder)';
  assert private.scan_passenger('320') and private.scan_passenger('32Q') and private.scan_passenger('E95')
     and not private.scan_passenger('77F') and not private.scan_passenger('74Y') and not private.scan_passenger('ABX')
     and not private.scan_passenger('ATF') and not private.scan_passenger('77X') and not private.scan_passenger('76X')
     and not private.scan_passenger('') and not private.scan_passenger(null),
    'private.scan_passenger() isn''t the weekly report''s seats() rule';
  raise notice 'freighters: Cargo Four''s 77F, 74Y, ABX and untyped flights on four of C1''s pairs are in no market share, threat, opening, profile or group line; the rule is the weekly report''s (a type ending in F, ATF, ABX, 74Y, 77X, 76X or none)';
end
$test$;

-- ---------------------------------------------------------------- 5. openings ranked, hubs first, the variant, the limit
do $test$
declare c1 bigint := (select (v #>> '{}')::bigint from t_cp where k = 'c1'); c2 bigint := (select (v #>> '{}')::bigint from t_cp where k = 'c2');
  t timestamptz := (select (v #>> '{}')::timestamptz from t_cp where k = 't'); w bigint := (select (v #>> '{}')::bigint from t_cp where k = 'w');
  d jsonb := (select v from t_cp where k = 'c1_doc'); got text; want text; o jsonb;
begin
  select string_agg((x ->> 'rank') || '. ' || (x ->> 'route') || ' ' || (x ->> 'stars') || '* ' || (x ->> 'rivals_weekly') || ' ' || (x ->> 'distance_km') || 'km '
                    || (x #>> '{variant,type}') || case when (x #>> '{variant,for_reach}')::boolean then ' (reach)' else '' end || ' '
                    || coalesce(x ->> 'allowed_by', 'NOT'), '; ' order by (x ->> 'rank')::int) into got
    from jsonb_array_elements(d -> 'openings') x;
  want := '1. YA1–YC2 5* 21 2000km CT A320 SHARP main hub; 2. YA1–YC1 5* 7 1000km CT A320 SHARP main hub; 3. YA1–YC3 4* 0 3000km CT E195 main hub; '
       || '4. YA1–YC4 4* 0 3800km CT E190 main hub; 5. YA2–YC9 3* 21 1500km CT E195 contested route; 6. YA3–YCA 3* 0 1500km CT E195 contested base; '
       || '7. YA1–YC6 3* 0 12000km CT A350-900 (reach) main hub; 8. YA1–YC7 3* 0 16000km CT A350-1000 (reach) main hub; 9. YA1–YC5 2* 0 5000km CT A321XLR (reach) main hub; '
       || '10. YA2–YC8 5* 0 1500km CT A320 SHARP NOT';
  assert got = want, 'C1''s openings are ' || coalesce(got, 'none');
  assert (d ->> 'openings_count')::int = 10 and (d ->> 'openings_allowed')::int = 9 and (d ->> 'openings_left_out')::int = 0
     and (d ->> 'pairs_flown')::int = 2 and (d ->> 'pairs_listed')::int = 13,
    'C1''s counts aren''t 10 openings, 9 allowed, none left out, 2 pairs flown of 13 listed: ' || jsonb_build_object('n', d -> 'openings_count', 'allowed', d -> 'openings_allowed', 'out', d -> 'openings_left_out', 'flown', d -> 'pairs_flown', 'listed', d -> 'pairs_listed')::text;
  select x into o from jsonb_array_elements(d -> 'openings') x where x ->> 'route' = 'YA2–YC8';
  assert not (o ->> 'allowed')::boolean
     and o ->> 'reason' = 'hubs first: YA1 at 14 of 750 departures a week, and YA2 isn''t contested (busiest rival there 50 a week, over 250 needed; none over 2 a day on YA2–YC8)',
    'YA2–YC8 isn''t marked not allowed with the reason: ' || o::text;
  select x into o from jsonb_array_elements(d -> 'openings') x where x ->> 'route' = 'YA1–YC2';
  assert (select string_agg(r ->> 'name' || ' ' || (r ->> 'weekly'), ', ' order by i) from jsonb_array_elements(o -> 'rivals') with ordinality e(r, i)) = 'Rival One 14, Rival Two 7'
     and o #>> '{variant,size}' = 'mid' and o #>> '{variant,seats}' = '189' and o ->> 'reason' is null and o ->> 'city' is null,
    'YA1–YC2''s rivals aren''t Rival One 14 and Rival Two 7, with a mid variant of 189 seats: ' || o::text;
  assert not exists (select 1 from jsonb_array_elements(d -> 'openings') x where x ->> 'route' in ('YA1–YB4', 'YA1–YCZ', 'YA1–YB2', 'YA1–YB3')),
    'a pair one of ours flies, or a removed route, is listed as an opening';
  -- p_limit: the top 3, the counts still all
  d := private.fig_competition(c1, t, 3);
  assert jsonb_array_length(d -> 'openings') = 3 and (d ->> 'openings_count')::int = 10 and d #>> '{openings,2,route}' = 'YA1–YC3',
    'p_limit 3 doesn''t give the top 3 with the counts of all: ' || (d -> 'openings')::text;
  -- once the main hub is at its target (C1's own target 10, under its 14), every base may open
  insert into public.settings (world_id, airline_id, key, value, unit, description) values (w, c1, 'hub_first_departures', '10'::jsonb, 'departures', 'test');
  d := private.fig_competition(c1, t);
  assert (select x ->> 'allowed_by' from jsonb_array_elements(d -> 'openings') x where x ->> 'route' = 'YA2–YC8') = 'main hub at its target'
     and d #>> '{openings,0,route}' = 'YA1–YC2' and (d ->> 'openings_allowed')::int = 10,
    'with the main hub at its target YA2–YC8 isn''t allowed: ' || (d -> 'openings')::text;
  delete from public.settings where world_id = w and airline_id = c1 and key = 'hub_first_departures';
  -- C2 may buy no A350: YB1–YD9 (8,000 km) is beyond every type it may buy, and left out
  d := private.fig_competition(c2, t);
  assert (select string_agg(x ->> 'route' || ' ' || (x #>> '{variant,type}'), ', ') from jsonb_array_elements(d -> 'openings') x) = 'YB1–YD1 CT E195'
     and (d ->> 'openings_left_out')::int = 1 and (d ->> 'openings_count')::int = 1,
    'C2''s 8,000 km route isn''t left out (no A350 for it): ' || (d -> 'openings')::text || ' left out ' || (d ->> 'openings_left_out');
  raise notice 'openings: 10 ranked by stars, rivals'' departures (YA1–YC2''s 21 before YA1–YC1''s 7), distance and code; YA2–YC8 (5 stars) last, not allowed under hubs first with its reason; YA2–YC9 a contested route, YA3–YCA a contested base; the E195 for a 4-star city, the E190 past the E195''s reach, the SHARP for 5 stars, the XLR for reach on a 2-star city, the A350-900 at 12,000 km and the -1000 at 16,000; p_limit 3; all open once the main hub is at its target; C2''s 8,000 km route left out (no A350)';
end
$test$;

-- ---------------------------------------------------------------- 6. rival profiles
do $test$
declare d jsonb := (select v from t_cp where k = 'c1_doc'); got text; p jsonb;
begin
  select string_agg(x ->> 'name' || ' ' || (x ->> 'pairs_shared') || '/' || (x ->> 'weekly_on_pairs'), ', ' order by i) into got
    from jsonb_array_elements(d -> 'profiles') with ordinality e(x, i);
  assert got = 'Rival Two 1/14, Rival One 1/7, Rival Three 1/6', 'the profiles are ' || coalesce(got, 'none');
  p := d -> 'profiles' -> 0;
  assert p ->> 'weekly' = '42' and p ->> 'weekly_before' = '35' and p ->> 'change' = '7' and p ->> 'airports' = '5'
     and p -> 'biggest_airports' = '[{"code": "YA2", "weekly": 21}, {"code": "YA1", "weekly": 14}, {"code": "YC2", "weekly": 7}]'::jsonb
     and p -> 'pairs' = '[{"ours": 14, "pair": "YA1-YB3", "route": "YA1–YB3", "weekly": 14}]'::jsonb,
    'Rival Two''s profile isn''t 42 passenger departures a week (35, +7), 5 airports, YA2, YA1 and YC2 its biggest, YA1–YB3 shared: ' || p::text;
  raise notice 'profiles: Rival Two, Rival One and Rival Three, each on one of C1''s pairs, by their departures on them; Rival Two 42 passenger departures a week (35 a week before), 5 airports, its biggest YA2, YA1 and YC2, from its schedule';
end
$test$;

-- ---------------------------------------------------------------- 7. one scan, none; who is refused; the copy
do $test$
declare c1 bigint := (select (v #>> '{}')::bigint from t_cp where k = 'c1'); sc jsonb := (select v from t_cp where k = 'scans'); d jsonb;
begin
  -- one finished scan (1 Feb): no week before, no previous, no threats; the share without a change
  d := private.fig_competition(c1, timestamptz '2030-02-01 12:00:00+00');
  assert d #>> '{scans,latest,id}' = sc ->> 's1' and d #> '{scans,week_before}' = 'null'::jsonb and d #> '{scans,previous}' = 'null'::jsonb
     and jsonb_array_length(d -> 'threats') = 0 and d #>> '{group,share_change}' is null and d #>> '{markets,0,share_change}' is null
     and (d #>> '{markets,0,share}')::numeric = 42.4 and jsonb_array_length(d -> 'openings') = 10,
    'with one scan: ' || jsonb_build_object('scans', d -> 'scans', 'threats', d -> 'threats', 'group', d -> 'group', 'm1', d -> 'markets' -> 0)::text;
  -- none (31 Jan): the openings by stars and distance, only the main hub's allowed; no group, no profiles, no threats
  d := private.fig_competition(c1, timestamptz '2030-01-31 12:00:00+00');
  assert d #> '{scans,latest}' = 'null'::jsonb and d -> 'group' = 'null'::jsonb and jsonb_array_length(d -> 'threats') = 0
     and jsonb_array_length(d -> 'profiles') = 0 and (d #>> '{markets,0,ours}')::int = 28 and d #>> '{markets,0,share}' is null
     and (d ->> 'openings_allowed')::int = 7 and d #>> '{openings,0,route}' = 'YA1–YC1'
     and (select x ->> 'reason' from jsonb_array_elements(d -> 'openings') x where x ->> 'route' = 'YA3–YCA')
         = 'hubs first: YA1 at 14 of 750 departures a week, and no world scan to show YA3 contested',
    'with no scan: ' || jsonb_build_object('scans', d -> 'scans', 'group', d -> 'group', 'openings', d -> 'openings')::text;
  raise notice 'one scan: no week before, previous or threats, the share without a change; none: no group, threats or profiles, the openings by stars and distance with only the main hub''s allowed';
end
$test$;

set local role anon;
do $test$
declare c1 bigint := (select (v #>> '{}')::bigint from t_cp where k = 'c1'); n int := 0;
begin
  begin perform public.competition(c1); exception when insufficient_privilege then n := n + 1; end;
  assert n = 1, 'signed out, competition() wasn''t refused';
end
$test$;
reset role;

do $$ begin perform set_config('request.jwt.claims',
  '{"sub": "00000000-0000-4000-8000-0000000000c1", "email": "competition-other@example.com", "role": "authenticated"}', true); end $$;
set local role authenticated;
do $test$
declare c1 bigint := (select (v #>> '{}')::bigint from t_cp where k = 'c1'); n int := 0;
begin
  begin perform public.competition(c1); exception when insufficient_privilege then n := n + 1; end;
  assert n = 1, 'an account that isn''t staff wasn''t refused competition()';
end
$test$;
reset role;

do $$ begin perform set_config('request.jwt.claims',
  '{"sub": "00000000-0000-4000-8000-0000000000c2", "email": "competition-staff@example.com", "role": "authenticated"}', true); end $$;
set local role authenticated;
do $test$
declare c1 bigint := (select (v #>> '{}')::bigint from t_cp where k = 'c1'); t timestamptz := (select (v #>> '{}')::timestamptz from t_cp where k = 't');
begin
  assert public.competition(c1, t) = (select v from t_cp where k = 'c1_doc'), 'staff don''t get what postgres gets from competition()';
end
$test$;
reset role;

-- ---------------------------------------------------------------- 8. November's trunks (manual §4)
do $test$
declare c1 bigint := (select (v #>> '{}')::bigint from t_cp where k = 'c1'); c2 bigint := (select (v #>> '{}')::bigint from t_cp where k = 'c2');
  w bigint := (select (v #>> '{}')::bigint from t_cp where k = 'w'); d jsonb; got text; want text;
  n_worlds int := (select count(*) from public.worlds x where x.id <> (select (v #>> '{}')::bigint from t_cp where k = 'w'));
begin
  -- every world but this test's own (which copied the default world's rows without their date and reason)
  assert (select count(*) from public.settings s where s.airline_id is null and s.world_id <> w and s.unit = 'date' and length(coalesce(s.description, '')) > 60 and s.reason is not null
            and ((s.key = 'trunk_month_from' and s.value = '"2026-11-01"'::jsonb) or (s.key = 'trunk_month_to' and s.value = '"2026-11-30"'::jsonb))) = 2 * n_worlds,
    'trunk_month_from and trunk_month_to aren''t 1 and 30 Nov 2026 in every world, described';
  perform set_config('equinox.actor', 'claude', true), set_config('equinox.actor_detail', 'competition test', true);
  -- trunks: YA1–YA3 (C1's main hub and focus city, 900 km), YA2–YB1 (C1's hub and C2's, 7,500 km, on C2's list too) and
  -- C2's YB1–YA3 (8,000 km: no type C2 may buy reaches it)
  perform pg_temp.cp_route(w, c1, 'YA1', 'YA3', 2, 900, null, false, null, 0);
  perform pg_temp.cp_route(w, c1, 'YA2', 'YB1', 1, 7500, null, false, null, 0);
  perform pg_temp.cp_route(w, c2, 'YB1', 'YA2', 1, 7500, null, false, null, 0);
  perform pg_temp.cp_route(w, c2, 'YB1', 'YA3', 3, 8000, null, false, null, 0);

  -- 10 Nov 2026 (no scan by then): the trunks first, shortest first, allowed; then the rest as always
  d := private.fig_competition(c1, timestamptz '2026-11-10 12:00:00+00');
  select string_agg((x ->> 'rank') || '. ' || (x ->> 'route') || case when (x ->> 'trunk')::boolean then ' trunk' else '' end || ' ' || coalesce(x ->> 'allowed_by', 'NOT')
                    || ' ' || (x #>> '{variant,type}') || case when jsonb_array_length(x -> 'other_lists') > 0 then ' also ' || (x ->> 'other_lists') else '' end,
                    '; ' order by (x ->> 'rank')::int) into got
    from jsonb_array_elements(d -> 'openings') x;
  want := '1. YA1–YA3 trunk November trunk CT E195; 2. YA2–YB1 trunk November trunk CT A350-900 also ["C2"]; '
       || '3. YA1–YC1 main hub CT A320 SHARP; 4. YA1–YC2 main hub CT A320 SHARP; 5. YA1–YC3 main hub CT E195; 6. YA1–YC4 main hub CT E190; '
       || '7. YA1–YC6 main hub CT A350-900; 8. YA1–YC7 main hub CT A350-1000; 9. YA1–YC5 main hub CT A321XLR; '
       || '10. YA2–YC8 NOT CT A320 SHARP; 11. YA2–YC9 NOT CT E195; 12. YA3–YCA NOT CT E195';
  assert got = want, 'C1''s openings on 10 Nov are ' || coalesce(got, 'none');
  assert d #> '{trunk_month}' = '{"on": true, "from": "2026-11-01", "to": "2026-11-30"}'::jsonb and (d ->> 'openings_trunks')::int = 2,
    'the trunk month isn''t on, 1 to 30 Nov, with 2 trunks: ' || jsonb_build_object('m', d -> 'trunk_month', 'n', d -> 'openings_trunks')::text;
  -- C2: its 7,500 and 8,000 km trunks not left out (the world's A350, not one it may buy); its 8,000 km non-trunk still is
  d := private.fig_competition(c2, timestamptz '2026-11-10 12:00:00+00');
  select string_agg((x ->> 'route') || ' ' || (x #>> '{variant,type}') || ' ' || (x #>> '{variant,own}'), '; ' order by (x ->> 'rank')::int) into got
    from jsonb_array_elements(d -> 'openings') x;
  assert got = 'YB1–YA2 CT A350-900 false; YB1–YA3 CT A350-900 false; YB1–YD1 CT E195 true' and (d ->> 'openings_left_out')::int = 1,
    'C2''s openings on 10 Nov are ' || coalesce(got, 'none') || ', left out ' || (d ->> 'openings_left_out');

  -- 31 Oct and 1 Dec: nothing changes (no trunk marks; hubs first as always; the long trunk left out for C2)
  foreach got in array array['2026-10-31 23:00:00+00', '2026-12-01 01:00:00+00'] loop
    d := private.fig_competition(c1, got::timestamptz);
    assert not exists (select 1 from jsonb_array_elements(d -> 'openings') x where (x ->> 'trunk')::boolean or x ->> 'allowed_by' = 'November trunk')
       and d #>> '{trunk_month,on}' = 'false' and (d ->> 'openings_trunks')::int = 0
       and (select string_agg(x ->> 'route' || ' ' || coalesce(x ->> 'allowed_by', 'NOT'), '; ' order by (x ->> 'rank')::int) from jsonb_array_elements(d -> 'openings') x)
           = 'YA1–YC1 main hub; YA1–YC2 main hub; YA1–YC3 main hub; YA1–YC4 main hub; YA1–YC6 main hub; YA1–YC7 main hub; YA1–YA3 main hub; YA1–YC5 main hub; '
          || 'YA2–YC8 NOT; YA2–YC9 NOT; YA3–YCA NOT; YA2–YB1 NOT',
      'on ' || got || ' the openings aren''t as always: ' || (d -> 'openings')::text;
    assert (private.fig_competition(c2, got::timestamptz) ->> 'openings_left_out')::int = 3, 'on ' || got || ' C2''s long trunks aren''t left out for reach as always';
  end loop;
  perform set_config('equinox.actor', '', true), set_config('equinox.actor_detail', '', true);
  raise notice 'November''s trunks: trunk_month_from and trunk_month_to (1 and 30 Nov 2026) in every world; on 10 Nov the trunks first, shortest first (YA1–YA3 900 km, then YA2–YB1 7,500 km, on C2''s list too), allowed with hubs first suspended, C2''s 7,500 and 8,000 km trunks on the world''s A350 rather than left out; then the rest as always; on 31 Oct and 1 Dec nothing changes';
end
$test$;

-- ---------------------------------------------------------------- 9. the A350 cut-over (spec docs/specs/2026-10-27-competition-a350-cutover.md)
-- The default line (manual §3, since 27 Oct): the A350-900 up to settings.a350_1000_from_km (14,200 km, its reach with a
-- full cabin), the -1000 beyond. The test's world copied the default world's row. YA1–YCE (3 stars, 14,100 km) and
-- YA1–YCF (14,200, at it) take CT A350-900, YA1–YCG (14,300) CT A350-1000. Moved to 14,000, YA1–YCE and YA1–YCF take the
-- -1000 too; C1's own row at 15,000 comes first (all three the -900); with no row at all, 14,200 again. No opening has
-- variant_alt or variant_note.
do $test$
declare c1 bigint := (select (v #>> '{}')::bigint from t_cp where k = 'c1'); w bigint := (select (v #>> '{}')::bigint from t_cp where k = 'w');
  t timestamptz := (select (v #>> '{}')::timestamptz from t_cp where k = 't'); d jsonb; got text; want text := 'YA1–YCE CT A350-900, YA1–YCF CT A350-900, YA1–YCG CT A350-1000';
  n_worlds int := (select count(*) from public.worlds x where x.id <> (select (v #>> '{}')::bigint from t_cp where k = 'w'));
begin
  -- every world but this test's own (which copied the default world's row without its date and reason)
  assert (select count(*) from public.settings s where s.key = 'a350_1000_from_km' and s.airline_id is null and s.world_id <> w and s.value = '14200'::jsonb
            and s.unit = 'km' and length(coalesce(s.description, '')) > 80 and s.since = date '2026-10-27' and s.reason ~ 'real-aircraft-reach') = n_worlds,
    'a350_1000_from_km isn''t 14200 km in every world, described, since 27 Oct, with its reason';
  assert (select s.value from public.settings s where s.world_id = w and s.airline_id is null and s.key = 'a350_1000_from_km') = '14200'::jsonb,
    'the test''s world didn''t copy a350_1000_from_km 14200 from the default world';
  perform set_config('equinox.actor', 'claude', true), set_config('equinox.actor_detail', 'competition test', true);
  insert into public.airports (code, utc_offset) select c, 0 from unnest(array['YCE', 'YCF', 'YCG']) c
  on conflict (code) do update set utc_offset = excluded.utc_offset;
  perform pg_temp.cp_route(w, c1, 'YA1', 'YCE', 3, 14100, null, false, null, 0);
  perform pg_temp.cp_route(w, c1, 'YA1', 'YCF', 3, 14200, null, false, null, 0);
  perform pg_temp.cp_route(w, c1, 'YA1', 'YCG', 3, 14300, null, false, null, 0);

  d := private.fig_competition(c1, t);
  select string_agg(x ->> 'route' || ' ' || (x #>> '{variant,type}'), ', ' order by x ->> 'route') into got
    from jsonb_array_elements(d -> 'openings') x where x ->> 'route' in ('YA1–YCE', 'YA1–YCF', 'YA1–YCG');
  assert got = want and (d #>> '{settings,wide_full_cabin_km}')::int = 14200,
    'at 14,200 km the openings are ' || coalesce(got, 'none') || ', wide_full_cabin_km ' || coalesce(d #>> '{settings,wide_full_cabin_km}', 'none');
  assert not exists (select 1 from jsonb_array_elements(d -> 'openings') x where x ? 'variant_alt' or x ? 'variant_note'),
    'an opening still has variant_alt or variant_note: ' || (d -> 'openings')::text;
  -- the 16,000 km opening stays on the -1000 and the 12,000 km one on the -900 (section 5)
  assert (select string_agg(x ->> 'route' || ' ' || (x #>> '{variant,type}'), ', ' order by x ->> 'route') from jsonb_array_elements(d -> 'openings') x
           where x ->> 'route' in ('YA1–YC6', 'YA1–YC7')) = 'YA1–YC6 CT A350-900, YA1–YC7 CT A350-1000',
    'YA1–YC6 and YA1–YC7 aren''t on the -900 and the -1000: ' || (d -> 'openings')::text;

  -- the setting moved: no code change
  update public.settings set value = '14000'::jsonb where world_id = w and airline_id is null and key = 'a350_1000_from_km';
  d := private.fig_competition(c1, t);
  select string_agg(x ->> 'route' || ' ' || (x #>> '{variant,type}'), ', ' order by x ->> 'route') into got
    from jsonb_array_elements(d -> 'openings') x where x ->> 'route' in ('YA1–YCE', 'YA1–YCF', 'YA1–YCG');
  assert got = 'YA1–YCE CT A350-1000, YA1–YCF CT A350-1000, YA1–YCG CT A350-1000' and (d #>> '{settings,wide_full_cabin_km}')::int = 14000,
    'at 14,000 km the openings are ' || coalesce(got, 'none') || ', wide_full_cabin_km ' || coalesce(d #>> '{settings,wide_full_cabin_km}', 'none');

  -- an airline's own row comes first
  insert into public.settings (world_id, airline_id, key, value, unit, description) values (w, c1, 'a350_1000_from_km', '15000'::jsonb, 'km', 'test');
  d := private.fig_competition(c1, t);
  select string_agg(x ->> 'route' || ' ' || (x #>> '{variant,type}'), ', ' order by x ->> 'route') into got
    from jsonb_array_elements(d -> 'openings') x where x ->> 'route' in ('YA1–YCE', 'YA1–YCF', 'YA1–YCG');
  assert got = 'YA1–YCE CT A350-900, YA1–YCF CT A350-900, YA1–YCG CT A350-900' and (d #>> '{settings,wide_full_cabin_km}')::int = 15000,
    'with C1''s own 15,000 km the openings are ' || coalesce(got, 'none') || ', wide_full_cabin_km ' || coalesce(d #>> '{settings,wide_full_cabin_km}', 'none');

  -- no row at all: 14,200 km
  delete from public.settings where world_id = w and key = 'a350_1000_from_km';
  d := private.fig_competition(c1, t);
  select string_agg(x ->> 'route' || ' ' || (x #>> '{variant,type}'), ', ' order by x ->> 'route') into got
    from jsonb_array_elements(d -> 'openings') x where x ->> 'route' in ('YA1–YCE', 'YA1–YCF', 'YA1–YCG');
  assert got = want and (d #>> '{settings,wide_full_cabin_km}')::int = 14200,
    'with no row the openings are ' || coalesce(got, 'none') || ', wide_full_cabin_km ' || coalesce(d #>> '{settings,wide_full_cabin_km}', 'none');
  perform set_config('equinox.actor', '', true), set_config('equinox.actor_detail', '', true);
  raise notice 'the A350 cut-over: a350_1000_from_km 14200 km in every world; YA1–YCE (14,100 km) and YA1–YCF (14,200) on CT A350-900, YA1–YCG (14,300) on CT A350-1000; at 14,000 all three on the -1000, with C1''s own 15,000 all on the -900, with no row 14,200 again; no opening with variant_alt or variant_note';
end
$test$;

-- ---------------------------------------------------------------- 10. the weekly report's three biggest competitors (spec docs/specs/2026-10-21-report-three-competitors.md)
-- At 13 Feb (latest s3, week before s1) C1 flies YA1–YB2 and YA1–YB3. On them in s3: Rival Two 14 (YA1→YB3 twice daily),
-- Rival One 7 (YA1→YB2, started in s3), Rival Three 6 (YB3→YA1 on six days); Cargo Four's freighters and C2 (ours) never.
-- Their whole passenger networks: Rival Two 42 (35 in s1), 5 airports; Rival One 28 (21; its s3 flight with no days not
-- counted), 4; Rival Three 13 (10), 4. C1 itself: 21 a week on its 2 pairs in both scans, 3 airports.
do $test$
declare c1 bigint := (select (v #>> '{}')::bigint from t_cp where k = 'c1'); c2 bigint := (select (v #>> '{}')::bigint from t_cp where k = 'c2');
  w bigint := (select (v #>> '{}')::bigint from t_cp where k = 'w'); t timestamptz := (select (v #>> '{}')::timestamptz from t_cp where k = 't');
  sc jsonb := (select v from t_cp where k = 'scans'); d jsonb := (select v from t_cp where k = 'c1_doc'); got text; r5 bigint; e jsonb;
begin
  -- the three, biggest on C1's pairs first, each with its network now and in the week-before scan
  select string_agg(format('%s. %s %s on %s pair(s), %s a week at %s airports, %s before, %s (%s%%)', x ->> 'rank', x ->> 'name', x ->> 'on_pairs',
                           x ->> 'pairs', x ->> 'weekly', x ->> 'airports', x ->> 'weekly_before', x ->> 'change', x ->> 'change_pct'), '; ' order by i)
    into got from jsonb_array_elements(d -> 'competitors') with ordinality e(x, i);
  assert got = '1. Rival Two 14 on 1 pair(s), 42 a week at 5 airports, 35 before, 7 (20.0%); 2. Rival One 7 on 1 pair(s), 28 a week at 4 airports, 21 before, 7 (33.3%); '
            || '3. Rival Three 6 on 1 pair(s), 13 a week at 4 airports, 10 before, 3 (30.0%)',
    'C1''s three biggest competitors are ' || coalesce(got, 'none');
  assert not exists (select 1 from jsonb_array_elements(d -> 'competitors') x where x ->> 'name' in ('Cargo Four', 'Comp Two')),
    'a freighter or our other airline is among C1''s competitors: ' || (d -> 'competitors')::text;
  -- self: C1 from the same scans' schedules
  assert d -> 'self' = jsonb_build_object('airline_id', c1, 'code', 'C1', 'name', 'Comp One', 'on_pairs', 21, 'pairs', 2, 'pairs_flown', 2,
                                         'weekly', 21, 'airports', 3, 'weekly_before', 21, 'change', 0, 'change_pct', 0.0),
    'C1''s self isn''t 21 a week on its 2 pairs, 21 in all at 3 airports, 21 before: ' || (d -> 'self')::text;
  -- C2 flies YB4→YA1, which no rival flies
  e := private.fig_competition(c2, t);
  assert e -> 'competitors' = '[]'::jsonb and e #>> '{self,on_pairs}' = '7' and e #>> '{self,pairs}' = '1' and e #>> '{self,weekly}' = '7',
    'C2 (no rival on its pair) isn''t no competitors and itself 7 on 1 pair: ' || jsonb_build_object('c', e -> 'competitors', 's', e -> 'self')::text;

  -- Rival Five, new in s3 (no schedule in s1 or s2): YA1→YB2 and YB3→YA1 daily (14 on C1's pairs, as Rival Two) and
  -- YB2→YC5 daily
  d := private.fig_competition(c1, t);
  perform set_config('equinox.actor', 'claude', true), set_config('equinox.actor_detail', 'competition test', true);
  insert into public.airlines (world_id, group_id, game_id, game_name, active) values (w, null, 990695, 'Rival Five', true) returning id into r5;
  insert into public.game_scan_schedules (scan_id, world_id, airline_id, flights)
  values ((sc ->> 's3')::bigint, w, r5, jsonb_build_array(pg_temp.cp_fl('R5', 1, 'YA1', 'YB2', '1234567'), pg_temp.cp_fl('R5', 2, 'YB3', 'YA1', '1234567'),
                                                          pg_temp.cp_fl('R5', 3, 'YB2', 'YC5', '1234567')));
  insert into public.game_scan_airlines (scan_id, world_id, enterprise_id, airline_id, name, n_flights, n_weekly, n_airports, position)
  values ((sc ->> 's3')::bigint, w, 990695, r5, 'Rival Five', 3, 21, 4, 7);
  perform set_config('equinox.actor', '', true), set_config('equinox.actor_detail', '', true);
  e := private.fig_competition(c1, t);
  select string_agg(format('%s. %s %s on %s, %s a week at %s, before %s, %s (%s)', x ->> 'rank', x ->> 'name', x ->> 'on_pairs', x ->> 'pairs',
                           x ->> 'weekly', x ->> 'airports', coalesce(x ->> 'weekly_before', 'none'), coalesce(x ->> 'change', 'none'),
                           coalesce(x ->> 'change_pct', 'none')), '; ' order by i)
    into got from jsonb_array_elements(e -> 'competitors') with ordinality e(x, i);
  assert got = '1. Rival Five 14 on 2, 21 a week at 4, before none, none (none); 2. Rival Two 14 on 1, 42 a week at 5, before 35, 7 (20.0); '
            || '3. Rival One 7 on 1, 28 a week at 4, before 21, 7 (33.3)',
    'with Rival Five, C1''s three are ' || coalesce(got, 'none');
  assert e #> '{competitors,0,weekly_before}' = 'null'::jsonb and e #> '{competitors,0,change}' = 'null'::jsonb
     and e #> '{competitors,0,change_pct}' = 'null'::jsonb and e -> 'self' = d -> 'self',
    'Rival Five (no row in the week-before scan) has a week-before figure, or C1''s self moved: ' || (e -> 'competitors' -> 0)::text;
  -- the rest of the document moves only where a new rival on C1's pairs should show (market share, threats, profiles and
  -- the group line)
  assert (e - 'competitors' - 'markets' - 'threats' - 'profiles' - 'group') = (d - 'competitors' - 'markets' - 'threats' - 'profiles' - 'group'),
    'adding a rival moved more than the rivals'' figures';

  -- one scan (1 Feb): no week-before figures; none (31 Jan): no competitors and no self
  e := private.fig_competition(c1, timestamptz '2030-02-01 12:00:00+00');
  assert (select string_agg(x ->> 'name' || ' ' || (x ->> 'on_pairs') || ' ' || (x ->> 'weekly') || ' ' || coalesce(x ->> 'weekly_before', 'none')
                            || ' ' || coalesce(x ->> 'change_pct', 'none'), ', ' order by (x ->> 'rank')::int) from jsonb_array_elements(e -> 'competitors') x)
         = 'Rival Two 7 35 none none, Rival Three 3 10 none none'
     and e #>> '{self,weekly}' = '21' and e #> '{self,weekly_before}' = 'null'::jsonb and e #> '{self,change}' = 'null'::jsonb,
    'with one scan: ' || jsonb_build_object('c', e -> 'competitors', 's', e -> 'self')::text;
  e := private.fig_competition(c1, timestamptz '2030-01-31 12:00:00+00');
  assert e -> 'competitors' = '[]'::jsonb and e -> 'self' = 'null'::jsonb,
    'with no scan: ' || jsonb_build_object('c', e -> 'competitors', 's', e -> 'self')::text;

  -- the export carries each airline's competitors, self and scans, as competition() gives them
  e := private.fig_export(w, t);
  assert (select string_agg(a ->> 'code', ',' order by i) from jsonb_array_elements(e -> 'airlines') with ordinality x(a, i)) = 'C1,C2'
     and (select bool_and(a -> 'competitors' = c -> 'competitors' and a -> 'self' = c -> 'self' and a -> 'scans' = c -> 'scans')
            from jsonb_array_elements(e -> 'airlines') a
            cross join lateral (select private.fig_competition((a ->> 'airline_id')::bigint, t, 0) as c) y)
     and jsonb_array_length(e #> '{airlines,0,competitors}') = 3 and e #>> '{airlines,0,scans,latest,taken_at}' = '2030-02-12T08:00:00.000Z',
    'the export''s competitors, self and scans aren''t competition()''s: ' || coalesce((e #> '{airlines,0}')::text, 'no airlines');
  raise notice 'the three biggest competitors: C1''s on its two pairs, Rival Two 14 (42 a week, 35 before, +20.0%%), Rival One 7 and Rival Three 6, freighters and our other airline never; self C1 21 on 2 pairs; C2 none on its pair; Rival Five, new, ties Rival Two at 14 and goes first by name, Rival Three out as the fourth, with no week-before figures; one scan, none before; no scan, none; the export carries them as competition() gives them';
end
$test$;

-- The new planner's Review screen and the plan card's service check (decision #18, build pull request 10). Spec:
-- docs/specs/2026-10-14-review.md ("every figure from the database's figures ... anything the old screen works out that
-- has no home yet goes to the database's figures (a new fig_* with a staff function), add only"; part 2: "if the service
-- profiles aren't in the rules input, add them to rules_input() (same arguments)").
--
-- Adds two staff functions with their builders and one setting, and changes four functions with the same arguments; takes
-- nothing away from anyone and changes no table's shape, so it can be applied from the chat:
--   private.rules_input_doc(p_world_id bigint, p_routes text): the document gains service_profiles (id, code, airline,
--     up to km; every row of the world, Ryanair's own R included), which the planning library's plan-card check reads
--     (lib/rules/src/service.ts). Everything else in it is as before, so rules_input() and export_for_report('rules')
--     answer as they did plus that one key.
--   public.cash_log(p_world_id, p_as_of) and its builder private.fig_cash_log(): Review's nightly log and the cash entry
--     form (the old planner's finSeries, applyCaptureCash and cashEntryHtml): per airline each reported date's cash and
--     fixed costs for the next 7 days, in millions, as the old planner shows them; and for today (UTC) the figures its
--     save compares a typed one with: what the tables hold (planner_state_get's cash and fixed7), the capture's, and the
--     typed row (cash_entries) with its updated_at.
--   public.fare_plan_status(p_airline_id, p_as_of) and its builder private.fig_fare_plan(): Review's fare plan (the old
--     planner's routeFares and farePlanStatus): each change still planned with the fare now, the target, whether the
--     captures show it (at least half the change, on or after the day it was proposed) and from when, and the economy load
--     before and after; and each route's latest captured economy fare (what "+ fare plan" starts from).
--   public.airline_profit(): each day gains per_aircraft_day (profit a day ÷ the aircraft flying that day; the old
--     table's last column, worked out on its screen).
--   public.route_profit(): average_flight gains income, costs, profit and margin (the old rpCost's sums, worked out on
--     its screen).
--   private.fig_group_today() (so airline_cards()): each airline's row gains leases_and_closing_day (this week's leases
--     and week-end closing per day together, the old board's left-hand bar).
--   settings.fare_plan_raise_pct (5, every world): the economy fare rise "+ fare plan" plans on a route that sells out (the
--     old planner's pct: 5 in its code; design §2, one source for rule numbers). The planner reads it through
--     rules_input(), which carries every setting.

select set_config('equinox.actor', 'migration', true),
       set_config('equinox.actor_detail', '20261014120000_review', true);

-- ============================================================ 1. rules_input(): the service profiles
create or replace function private.rules_input_doc(p_world_id bigint, p_routes text default 'all')
 returns jsonb
 language plpgsql
 stable
 set search_path to ''
as $function$
declare
  w bigint;
  v_name text;
begin
  if p_routes is null or p_routes not in ('all', 'flown') then
    raise exception 'rules_input: p_routes must be all or flown, not %', coalesce(p_routes, 'null') using errcode = '22023';
  end if;
  select x.id, x.name into w, v_name from public.worlds x where x.id = p_world_id or (p_world_id is null and x.is_default);
  if w is null then raise exception 'no such world: %', coalesce(p_world_id::text, 'no default world') using errcode = '22023'; end if;
  return (
    with
    -- the routes the document holds: every route that isn't removed, or with 'flown' only those that have rotations
    rts as (
      select r.* from public.routes r
       where r.world_id = w and not r.removed
         and (p_routes = 'all' or exists (select 1 from public.rotations ro where ro.route_id = r.id))),
    -- the airlines the planning rows name, and every airline of our groups (the same with 'all' and 'flown')
    named(id) as (
      select b.airline_id from public.airline_bases b where b.world_id = w
      union select a.airline_id from public.aircraft a where a.world_id = w
      union select r.airline_id from public.routes r where r.world_id = w and not r.removed
      union select r.airline_id from public.rotations r where r.world_id = w
      union select l.airline_id from public.flight_legs l where l.world_id = w
      union select al.id from public.airlines al join public.groups g on g.id = al.group_id and g.world_id = al.world_id
             where al.world_id = w and g.kind = 'ours'),
    -- every airport the document's routes, a leg, a base or an aircraft's base uses
    codes(code) as (
      select r.hub_code from rts r
      union select r.dest_code from rts r
      union select l.origin_code from public.flight_legs l where l.world_id = w
      union select l.dest_code from public.flight_legs l where l.world_id = w
      union select b.airport_code from public.airline_bases b where b.world_id = w
      union select a.base_code from public.aircraft a where a.world_id = w and a.base_code is not null)
    select jsonb_build_object(
      'world', jsonb_build_object('id', w, 'name', v_name),
      'settings', (select coalesce(jsonb_object_agg(s.key, s.value order by s.key), '{}'::jsonb)
                     from public.settings s where s.world_id = w and s.airline_id is null),
      'world_rules', (select coalesce(jsonb_object_agg(r.key, r.value order by r.key), '{}'::jsonb)
                        from public.world_rules r where r.world_id = w),
      'aircraft_types', (select coalesce(jsonb_agg(jsonb_build_object(
                            'id', t.id, 'name', t.name, 'family_no', t.family_no, 'seats_max', t.seats_max, 'cruise_kmh', t.cruise_kmh,
                            'min_turn_min', t.min_turn_min, 'gap_target_h', t.gap_target_h, 'maint_per_cycle', t.maint_per_cycle,
                            'maint_per_hour', t.maint_per_hour, 'ground_keep_min', t.ground_keep_min) order by t.id), '[]'::jsonb)
                           from public.aircraft_types t where t.world_id = w),
      'cabin_configs', (select coalesce(jsonb_agg(jsonb_build_object(
                           'id', c.id, 'code', c.code, 'aircraft_type_id', c.aircraft_type_id, 'seats', c.seats) order by c.id), '[]'::jsonb)
                          from public.cabin_configs c where c.world_id = w),
      'airports', (select coalesce(jsonb_agg(jsonb_build_object(
                      'code', k.code, 'city', a.city, 'country_code', a.country_code, 'lat', a.lat, 'lon', a.lon,
                      'utc_offset', coalesce(wa.utc_offset_override, a.utc_offset), 'utc_offset_override', wa.utc_offset_override,
                      'mct_min', wa.mct_min, 'night_ban_from', to_char(wa.night_ban_from, 'HH24:MI'), 'night_ban_to', to_char(wa.night_ban_to, 'HH24:MI'),
                      'closed', coalesce(wa.closed, false)) order by k.code collate "C"), '[]'::jsonb)
                     from codes k
                     left join public.airports a on a.code = k.code
                     left join public.world_airports wa on wa.world_id = w and wa.airport_code = k.code),
      'airlines', (select coalesce(jsonb_agg(jsonb_build_object(
                      'id', al.id, 'iata_code', al.iata_code, 'game_id', al.game_id, 'game_name', al.game_name, 'planner_name', al.planner_name,
                      'public_name', al.public_name, 'position', al.position, 'active', al.active, 'ours', coalesce(g.kind = 'ours', false),
                      -- the settings as they apply to this airline: its own override of a key in place of the world's value
                      'settings', (select coalesce(jsonb_object_agg(s.key, s.value order by s.key), '{}'::jsonb)
                                     from (select distinct on (st.key) st.key, st.value from public.settings st
                                            where st.world_id = w and (st.airline_id is null or st.airline_id = al.id)
                                            order by st.key, st.airline_id nulls last) s))
                      order by al.position nulls last, al.id), '[]'::jsonb)
                     from public.airlines al
                     left join public.groups g on g.id = al.group_id and g.world_id = al.world_id
                    where al.world_id = w and al.id in (select n.id from named n)),
      'airline_bases', (select coalesce(jsonb_agg(jsonb_build_object(
                           'id', b.id, 'airline_id', b.airline_id, 'airport_code', b.airport_code, 'role', b.role, 'is_main', b.is_main,
                           'parent_base_id', b.parent_base_id, 'parent_code', pb.airport_code,
                           'bank_times', (select jsonb_agg(to_char(t, 'HH24:MI') order by o) from unnest(b.bank_times) with ordinality as u(t, o)),
                           'flight_no_from', b.flight_no_from, 'last_flight_no', b.last_flight_no, 'position', b.position)
                           order by b.position nulls last, b.id), '[]'::jsonb)
                          from public.airline_bases b left join public.airline_bases pb on pb.id = b.parent_base_id
                         where b.world_id = w),
      'aircraft', (select coalesce(jsonb_agg(jsonb_build_object(
                      'id', a.id, 'registration', a.registration, 'airline_id', a.airline_id, 'aircraft_type_id', a.aircraft_type_id,
                      'cabin_config_id', a.cabin_config_id, 'base_code', a.base_code, 'status', a.status) order by a.id), '[]'::jsonb)
                     from public.aircraft a where a.world_id = w),
      'routes', (select coalesce(jsonb_agg(jsonb_build_object(
                    'id', r.id, 'airline_id', r.airline_id, 'hub_code', r.hub_code, 'dest_code', r.dest_code,
                    'distance_km', coalesce(r.distance_override_km, r.distance_km),
                    'market_id', m.id, 'market', m.name) order by r.id), '[]'::jsonb)
                   from rts r
                   left join public.markets m on m.id = case when r.market_cleared then null else coalesce(r.market_override_id, r.market_id) end),
      'rotations', (select coalesce(jsonb_agg(jsonb_build_object(
                       'id', r.id, 'airline_id', r.airline_id, 'route_id', r.route_id, 'legacy_key', r.legacy_key) order by r.id), '[]'::jsonb)
                      from public.rotations r where r.world_id = w),
      'flight_legs', (select coalesce(jsonb_agg(jsonb_build_object(
                         'id', l.id, 'airline_id', l.airline_id, 'rotation_id', l.rotation_id, 'leg_no', l.leg_no, 'flight_no', l.flight_no,
                         'origin_code', l.origin_code, 'dest_code', l.dest_code, 'aircraft_id', l.aircraft_id, 'days_utc', to_jsonb(l.days_utc),
                         'dep_utc_min', l.dep_utc_min, 'block_min', l.block_min) order by l.rotation_id, l.leg_no, l.id), '[]'::jsonb)
                        from public.flight_legs l where l.world_id = w),
      -- the service profiles (service_profiles), for the plan card's service check (#18 build pull request 10)
      'service_profiles', (select coalesce(jsonb_agg(jsonb_build_object(
                              'id', s.id, 'code', s.code, 'airline_id', s.airline_id, 'up_to_km', s.up_to_km) order by s.id), '[]'::jsonb)
                             from public.service_profiles s where s.world_id = w))
  );
end
$function$;

comment on function private.rules_input_doc(bigint, text) is 'The planning library''s input for a world (decision #19, design §7), with no check of its own: what rules_input() gives staff and export_for_report(''rules'') gives the scripts (always ''all''). See rules_input(). p_world_id: the world, or null for the default world; p_routes: all (every route that isn''t removed) or flown (only routes with rotations, and only the airports they, the legs, the bases and the aircraft use).';
comment on function public.rules_input(bigint, text) is 'Everything the planning library (lib/rules/, decision #19, design §7) needs, in one JSON document for the world (the default world when null): settings (the world''s values) and world_rules, as key → value; aircraft_types (cruise, turn, maintenance per cycle and hour, ground keep, seats); cabin_configs; every airport any route, leg or base uses (position, UTC offset with the world''s correction applied, minimum connection time, night ban as local HH:MM); airlines (ours and any the planning rows name), each with its settings as they apply to it (its own overrides in place of the world''s values); airline_bases (role, bank times as HH:MM, flight-number block, last number used); aircraft; routes that aren''t removed (distance and market with any override applied); rotations; flight_legs (UTC weekdays, departure minute and block time), by rotation and leg; and service_profiles (code, airline or none for the shared ones, up to km), for the plan card''s service check (#18 build pull request 10). p_routes: all (the default) or flown, the new planner''s lighter start (#18, design §5): only the routes that have rotations, and only the airports they, the legs, the bases and the aircraft use; the rest of the document is the same. The new planner (flown), the scripts (export_for_report(''rules''), all) and Claude''s command (node lib/rules/dist/cli.js) build the library''s Rules object from it. Staff only; runs as owner and checks the caller itself.';

-- ============================================================ 2. the nightly log and the cash entry form
-- finSeries() (the reported days and their cash: fig_cash_days), with each day's fixed costs as the old planner holds
-- them after applyCaptureCash(): for a capture day in the last 7 days (CAP.bal, the day's latest balance) the events'
-- payments in the 7 days after that balance was captured, rounded to 0.01M, when there are any; otherwise the tables'
-- figure (planner_state_get's fixed7: a typed one, else the capture's rounded, shown only above zero)
create or replace function private.fig_cash_log(p_world_id bigint, p_as_of timestamptz)
 returns jsonb
 language plpgsql
 stable
 set search_path to ''
as $function$
declare
  v_today date := (p_as_of at time zone 'UTC')::date;
begin
  return (
    with al as materialized (select * from private.fig_airlines(p_world_id)),
    cd as (select al.airline_id, c.day, c.cash from al cross join lateral private.fig_cash_days(al.airline_id, p_as_of) c),
    typed as (select e.airline_id, e.day, e.cash, e.fixed_next7, e.updated_at from public.cash_entries e where e.world_id = p_world_id),
    cap as (select cc.airline_id, cc.day, cc.cash, cc.fixed_next7 from public.capture_cash cc where cc.world_id = p_world_id),
    bal as (select distinct on (b.airline_id, b.captured_on) b.airline_id, b.captured_on as day, b.captured_at
              from public.game_balance b join al on al.airline_id = b.airline_id and al.home_code is not null
             where b.account like '2800%' and b.captured_on >= v_today - 7 and b.captured_on <= v_today and b.captured_at <= p_as_of
               and b.amount is not null
             order by b.airline_id, b.captured_on, b.captured_at desc),
    ev as materialized (select e.airline_id, e.at, e.amount from private.fig_events(p_world_id, p_as_of) e),
    fx as (select bal.airline_id, bal.day,
                  (select sum(ev.amount) from ev where ev.airline_id = bal.airline_id and ev.at > bal.captured_at
                                                   and ev.at <= bal.captured_at + interval '168 hours') as m
             from bal),
    -- the tables' figures for an airline and day (planner_state_get), the capture's rounded as the planner rounds
    pair as (select coalesce(t.airline_id, c.airline_id) as airline_id, coalesce(t.day, c.day) as day,
                    coalesce(t.cash / 1000000, floor(c.cash / 10000 + 0.5) / 100) as stored_cash,
                    case when coalesce(t.fixed_next7, c.fixed_next7) > 0
                         then case when t.fixed_next7 is not null then t.fixed_next7 / 1000000 else floor(c.fixed_next7 / 10000 + 0.5) / 100 end end as stored_fixed,
                    floor(c.cash / 10000 + 0.5) / 100 as captured_cash,
                    case when c.fixed_next7 > 0 then floor(c.fixed_next7 / 10000 + 0.5) / 100 end as captured_fixed,
                    t.airline_id is not null as typed, t.cash as typed_cash, t.fixed_next7 as typed_fixed, t.updated_at as typed_at
               from typed t full join cap c on c.airline_id = t.airline_id and c.day = t.day),
    shown as (select cd.airline_id, cd.day, cd.cash,
                     case when fx.m > 0 then floor(fx.m * 100 + 0.5) / 100 else p.stored_fixed end as fixed
                from cd
                left join fx on fx.airline_id = cd.airline_id and fx.day = cd.day
                left join pair p on p.airline_id = cd.airline_id and p.day = cd.day)
    select jsonb_build_object(
      'world_id', p_world_id, 'as_of', private.fig_ts(p_as_of), 'today', v_today,
      'airlines', coalesce(jsonb_agg(jsonb_build_object(
          'airline_id', al.airline_id, 'code', al.iata_code, 'name', al.name,
          'days', (select coalesce(jsonb_agg(jsonb_build_object('day', s.day, 'cash', trim_scale(s.cash), 'fixed', trim_scale(s.fixed)) order by s.day), '[]'::jsonb)
                     from shown s where s.airline_id = al.airline_id),
          'today', (select jsonb_build_object(
                      'day', v_today,
                      'shown_cash', (select trim_scale(s.cash) from shown s where s.airline_id = al.airline_id and s.day = v_today),
                      'shown_fixed', coalesce((select trim_scale(s.fixed) from shown s where s.airline_id = al.airline_id and s.day = v_today),
                                              (select trim_scale(p.stored_fixed) from pair p where p.airline_id = al.airline_id and p.day = v_today)),
                      'stored_cash', trim_scale(p.stored_cash), 'stored_fixed', trim_scale(p.stored_fixed),
                      'captured_cash', trim_scale(p.captured_cash), 'captured_fixed', trim_scale(p.captured_fixed),
                      'entry', case when coalesce(p.typed, false) then jsonb_build_object('cash', p.typed_cash, 'fixed_next7', p.typed_fixed, 'updated_at', p.typed_at) end)
                      from (select 1) one left join pair p on p.airline_id = al.airline_id and p.day = v_today))
          order by al.ord), '[]'::jsonb))
      from al);
end
$function$;

create or replace function public.cash_log(p_world_id bigint default null, p_as_of timestamptz default now())
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to ''
as $function$
begin
  if not private.caller_is_staff() then raise exception 'only planner staff can read the captured figures' using errcode = '42501'; end if;
  return private.fig_cash_log(private.fig_world(p_world_id), coalesce(p_as_of, now()));
end
$function$;

revoke all on function private.fig_cash_log(bigint, timestamptz) from public, anon, authenticated, service_role;
revoke all on function public.cash_log(bigint, timestamptz) from public, anon, authenticated, service_role;
grant execute on function public.cash_log(bigint, timestamptz) to authenticated;

comment on function private.fig_cash_log(bigint, timestamptz) is 'The captured figures (#19): builds cash_log()''s document with no check of its own. See cash_log().';
comment on function public.cash_log(bigint, timestamptz) is 'Review''s nightly log and its cash entry form for our active airlines in a world (the default world when null), in display order (#18 build pull request 10; the old planner''s finSeries, applyCaptureCash and cashEntryHtml): per airline each reported date (airline_profit()''s, the first included) with its cash and its fixed costs for the next 7 days as the old planner shows them (for a capture day in the 7 days to p_as_of''s UTC date, the events'' payments in the 7 days after that day''s latest balance, when there are any; otherwise a typed figure, else the capture''s, above zero only); and for today (p_as_of''s UTC date) the figures a typed one is saved against: shown (the form''s), stored (what the tables give the old planner: a typed figure, else the capture''s rounded to 0.01M), captured (capture_cash rounded) and the typed row (cash_entries: cash and fixed_next7 in AS$, updated_at) when there is one. Money in millions of AS$ unless named. Staff only; runs as owner and checks the caller itself.';

-- ============================================================ 3. the fare plan
-- routeFares() and farePlanStatus(): an airline's captured economy fares and loads by date for each of its routes, both
-- directions (CAP.loads: the last 9 days' loads rows, one per date and flight number, the latest row), and each fare
-- change still planned against them
create or replace function private.fig_fare_plan(p_airline_id bigint, p_as_of timestamptz)
 returns jsonb
 language plpgsql
 stable
 set search_path to ''
as $function$
declare
  w bigint := private.fig_airline_world(p_airline_id);
  v_today date := (p_as_of at time zone 'UTC')::date;
begin
  return (
    with l as (select distinct on (f.game_date, f.flight_no) f.game_date, f.origin_code as origin, f.dest_code as dest,
                      f.eco_pct as eco, trim_scale(f.eco_fare) as fare
                 from public.game_flights f
                where f.airline_id = p_airline_id and f.flight_no is not null and f.game_date >= v_today - 9
                  and f.loads_captured_at <= p_as_of
                order by f.game_date, f.flight_no, f.id desc),
    r as (select ro.id, ro.hub_code, ro.dest_code from public.routes ro where ro.airline_id = p_airline_id and ro.world_id = w),
    -- each route's fares and economy loads by date: the day's average fare, and the loads summed with their count (the
    -- before and after are averages over every flight, not over the days)
    rd as materialized (
      select r.id as route_id, l.game_date as day, avg(l.fare) as fare, sum(l.eco) as eco_sum, count(l.eco) as eco_n
        from r join l on l.fare is not null
         and ((l.origin = r.hub_code and l.dest = r.dest_code) or (l.origin = r.dest_code and l.dest = r.hub_code))
       group by r.id, l.game_date),
    p as (select fp.*, ro.hub_code, ro.dest_code,
                 fp.fare_from * (1 + fp.change_pct / 100) as target,
                 (select rd.fare from rd where rd.route_id = fp.route_id order by rd.day desc limit 1) as cur,
                 -- seen once at least half the change shows in the day's average fare, on or after the day it was proposed
                 (select min(rd.day) from rd where rd.route_id = fp.route_id and rd.day >= fp.proposed_on
                     and rd.fare >= fp.fare_from * (1 + fp.change_pct / 200)) as seen
            from public.fare_plan fp left join public.routes ro on ro.id = fp.route_id
           where fp.airline_id = p_airline_id and fp.status <> 'dropped')
    select jsonb_build_object(
      'airline_id', p_airline_id, 'as_of', private.fig_ts(p_as_of),
      'plan', coalesce((select jsonb_agg(jsonb_build_object(
                 'id', p.id, 'legacy_key', p.legacy_key, 'route_id', p.route_id, 'hub', p.hub_code, 'dest', p.dest_code,
                 'cabin_class', p.cabin_class, 'change_pct', trim_scale(p.change_pct), 'fare_from', trim_scale(p.fare_from),
                 'proposed_on', p.proposed_on, 'status', p.status, 'reason', p.reason, 'updated_at', p.updated_at,
                 'fare_now', p.cur, 'target', p.target, 'applied', p.seen is not null, 'seen_on', p.seen,
                 'economy_before', case when p.seen is not null
                                        then (select sum(rd.eco_sum) / nullif(sum(rd.eco_n), 0) from rd where rd.route_id = p.route_id and rd.day < p.seen) end,
                 'economy_after', case when p.seen is not null
                                       then (select sum(rd.eco_sum) / nullif(sum(rd.eco_n), 0) from rd where rd.route_id = p.route_id and rd.day >= p.seen) end)
                 order by p.id) from p), '[]'::jsonb),
      'fares', coalesce((select jsonb_agg(jsonb_build_object('route_id', x.route_id, 'hub', r.hub_code, 'dest', r.dest_code, 'day', x.day, 'fare', x.fare)
                                          order by x.route_id)
                           from (select distinct on (rd.route_id) rd.route_id, rd.day, rd.fare from rd order by rd.route_id, rd.day desc) x
                           join r on r.id = x.route_id), '[]'::jsonb)));
end
$function$;

create or replace function public.fare_plan_status(p_airline_id bigint, p_as_of timestamptz default now())
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to ''
as $function$
begin
  if not private.caller_is_staff() then raise exception 'only planner staff can read the captured figures' using errcode = '42501'; end if;
  return private.fig_fare_plan(p_airline_id, coalesce(p_as_of, now()));
end
$function$;

revoke all on function private.fig_fare_plan(bigint, timestamptz) from public, anon, authenticated, service_role;
revoke all on function public.fare_plan_status(bigint, timestamptz) from public, anon, authenticated, service_role;
grant execute on function public.fare_plan_status(bigint, timestamptz) to authenticated;

comment on function private.fig_fare_plan(bigint, timestamptz) is 'The captured figures (#19): builds fare_plan_status()''s document with no check of its own. See fare_plan_status().';
comment on function public.fare_plan_status(bigint, timestamptz) is 'Review''s fare plan for one airline (#18 build pull request 10; the old planner''s routeFares and farePlanStatus), from the economy fares and loads its captures give for each of its routes, both directions (the last 9 days'' loads, one per date and flight number): plan, each fare change not dropped (fare_plan, by id) with its row''s fields and updated_at, the fare now (the latest captured day''s average), the target (fare then × (1 + change)), applied and seen_on (the first captured day on or after it was proposed whose average fare shows at least half the change) and the average economy load before and after that day; and fares, each route''s latest captured day with its average economy fare (what "+ fare plan" starts from). Staff only; runs as owner and checks the caller itself.';

-- ============================================================ 4. figures the old Review worked out on its screen
-- airline_profit(): each interval's profit a day per aircraft flying that day (the old table's "Per aircraft")
create or replace function public.airline_profit(p_airline_id bigint, p_as_of timestamptz default now())
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to ''
as $function$
declare d jsonb;
begin
  if not private.caller_is_staff() then raise exception 'only planner staff can read the captured figures' using errcode = '42501'; end if;
  d := private.fig_fin_stats(p_airline_id, coalesce(p_as_of, now()));
  return jsonb_build_object('airline_id', p_airline_id, 'as_of', d -> 'as_of', 'profit_day', d -> 'profit_day',
                            'span_days', d -> 'span_days', 'early', d -> 'early',
                            'days', (select coalesce(jsonb_agg(x || jsonb_build_object('per_aircraft_day',
                                              case when coalesce((x ->> 'aircraft')::int, 0) <> 0
                                                   then (x ->> 'profit_day')::numeric / (x ->> 'aircraft')::int end) order by i), '[]'::jsonb)
                                       from jsonb_array_elements(d -> 'days') with ordinality as e(x, i)));
end
$function$;

comment on function public.airline_profit(bigint, timestamptz) is 'Profit for each day between captures for one airline (decision #19, design §8; the old planner''s finSeries, finStats, capexIn and dayOps): each reported cash date (the capture''s balance rounded to 0.01M, or a figure typed in cash_entries) with the change in cash plus that period''s order payments (orders and cabins; losses stay in profit), per day over the days between, the aircraft, flights and average load flown that day, and the profit a day per aircraft flying that day (per_aircraft_day, #18 build pull request 10); with the 7-day profit a day. Money in millions of AS$. Staff only; runs as owner and checks the caller itself.';

-- route_profit(): the average flight's income, costs, profit and margin (the old rpCost)
create or replace function public.route_profit(p_airline_id bigint, p_days integer default 7, p_as_of timestamptz default now())
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to ''
as $function$
declare d jsonb; a jsonb; v_in numeric; v_out numeric;
begin
  if not private.caller_is_staff() then raise exception 'only planner staff can read the captured figures' using errcode = '42501'; end if;
  d := private.fig_route_profit(p_airline_id, p_days, coalesce(p_as_of, now())) - 'aircraft' - 'fare_changes';
  a := d -> 'average_flight';
  if jsonb_typeof(a) = 'object' then
    v_in := coalesce((a ->> 'passengers')::numeric, 0) + coalesce((a ->> 'cargo')::numeric, 0);
    v_out := coalesce((a ->> 'fuel')::numeric, 0) + coalesce((a ->> 'handling')::numeric, 0) + coalesce((a ->> 'onboard')::numeric, 0)
           + coalesce((a ->> 'landing')::numeric, 0) + coalesce((a ->> 'air_traffic')::numeric, 0) + coalesce((a ->> 'maintenance')::numeric, 0);
    d := jsonb_set(d, '{average_flight}', a || jsonb_build_object('income', v_in, 'costs', v_out, 'profit', v_in - v_out,
                                                                   'margin', case when v_in <> 0 then (v_in - v_out) / v_in end));
  end if;
  return d;
end
$function$;

comment on function public.route_profit(bigint, integer, timestamptz) is 'Each route''s profit over the last p_days (1, 3 or 7; decision #19, design §8; the old planner''s routeProfit): every bank-statement block with one route, matched to the nearest loads row of that route departing within 31 minutes, grouped by the route as the airline has it: flights, profit, income, margin, profit a flight and a week (× flights a week planned), average economy, business and cargo load and economy fare, departures sold out and their share, and the mark (add a flight, raise fares, fix or reduce, losing money, hold) from the growth_* settings, with why; plus how many flights, how many matched to loads, blocks with several routes (mixed), and the average flight''s income and costs, with their sums, its profit and its margin (#18 build pull request 10, the old rpCost). Money in millions of AS$. Staff only; runs as owner and checks the caller itself.';

-- groupOverviewHtml(): as 20261012210000_captured_figures.sql left it, with this week's leases and week-end closing per
-- day together (the old board's left-hand bar)
create or replace function private.fig_group_today(p_airline_id bigint, p_as_of timestamptz)
 returns jsonb
 language plpgsql
 stable
 set search_path to ''
as $function$
declare
  w bigint := private.fig_airline_world(p_airline_id);
  v_today date := (p_as_of at time zone 'UTC')::date;
  v_cash numeric; v_flights bigint; v_income numeric; v_costs numeric; v_ops numeric; v_fpd numeric;
  v_ground text[]; v_lease numeric; v_closing numeric; v_ground_lease numeric;
begin
  select b.amount / 1000000 into v_cash from public.game_balance b
   where b.airline_id = p_airline_id and b.account like '2800%' and b.captured_on >= v_today - 7 and b.captured_at <= p_as_of
   order by b.captured_at desc limit 1;
  select o.flights, o.income, o.costs into v_flights, v_income, v_costs from private.fig_ops_recent(p_airline_id, p_as_of) o;
  if v_flights >= 5 then
    select coalesce(sum(f.flights_week::numeric / 7), 0) into v_fpd from private.fig_freqs(w, p_airline_id) f where f.live and f.airline_id = p_airline_id;
    v_ops := (v_income - v_costs) / v_flights * v_fpd / 1000000;
  end if;
  select coalesce(array_agg(a.registration order by a.delivery_at, a.registration), '{}') into v_ground
    from public.aircraft a
   where a.airline_id = p_airline_id and a.status in ('on_order', 'delivered') and a.delivery_at <= p_as_of;
  select coalesce(sum(e.amount) filter (where e.descr ~* 'Leasing payment'), 0) / 7,
         coalesce(sum(e.amount) filter (where e.descr ~* 'Week-end closing'), 0) / 7,
         coalesce(sum(e.amount) filter (where exists (select 1 from unnest(v_ground) g where strpos(e.descr, g || ' ') > 0)), 0) / 7
    into v_lease, v_closing, v_ground_lease
    from private.fig_events(w, p_as_of, p_airline_id) e
   where e.airline_id = p_airline_id and e.at > p_as_of and e.at <= p_as_of + interval '168 hours';
  return jsonb_build_object('airline_id', p_airline_id, 'cash', v_cash, 'flight_profit_day', v_ops,
                            'leases_day', v_lease, 'closing_day', v_closing, 'leases_and_closing_day', v_lease + v_closing,
                            'net_day', v_ops - v_lease - v_closing,
                            'on_ground', to_jsonb(v_ground), 'on_ground_lease_day', v_ground_lease);
end
$function$;

comment on function private.fig_group_today(bigint, timestamptz) is 'The captured figures (#19): one airline''s row of the group today (groupOverviewHtml), with no check of its own: cash, flight profit a day, this week''s leases and week-end closing per day (each, and together since #18 build pull request 10), net, and the aircraft arrived but not yet flying with their leases a day. See airline_cards().';
comment on function public.airline_cards(bigint, timestamptz) is 'Review''s card for each of our active airlines in a world (the default world when null), in display order (decision #19, design §8; the old planner''s finStats, renderFinance and fcNext): profit a day over the last 7 days of reported cash (an early read over fewer, early true), per aircraft, return on fleet a week, an aircraft pays back in and funds a new aircraft every (days), fleet, on order, flights a day and how many more than a week ago, average load over 7 days, next_order and can_order_now (cash_forecast()); and group_today (groupOverviewHtml): per airline cash, flight profit a day, this week''s leases and week-end closing per day (each, and together), net, and aircraft arrived but not yet flying with their leases a day (group_today_shown once any airline has flight profit). No group totals (manual §1). Money in millions of AS$. And the group''s average economy load over 7 days, the old Home''s key figure (avgLF): load_7_days, the average of every flight the loads pages captured departing from 7 days before p_as_of''s UTC date on (one per airline, date and flight number), with load_7_days_flights and load_7_days_from captures; with none captured, every flight the last 7 days'' load reports cover (route_loads()), from reports; with neither, null. Staff only; runs as owner and checks the caller itself.';

-- ============================================================ 5. the fare plan's step
insert into public.settings (world_id, airline_id, key, value, unit, description, since, reason)
select w.id, null, 'fare_plan_raise_pct', '5'::jsonb, 'percent',
       'Review → Route profit''s "+ fare plan": the economy fare rise planned on a route that sells out (the old planner''s pct: 5)',
       date '2026-10-14', 'The old planner''s 5%, given a home of its own (#19)'
  from public.worlds w
on conflict on constraint settings_world_airline_key_key do nothing;

select set_config('equinox.actor', '', true), set_config('equinox.actor_detail', '', true);

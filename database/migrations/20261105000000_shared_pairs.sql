-- Shared city pairs, pull request 1 of 3: the data and the fare ladder (5 Nov 2026; spec docs/specs/2026-11-05-shared-pairs.md
-- §1 and §2, brief docs/briefs/2026-11-04-shared-pairs.md, option B with Ryanair out, decided by Gitesh on 4 Nov: "I want b
-- tomorrow i think. It seems like how a real consortium would operate").
--
-- Why: a pair whose two airports are bases (hub or focus city) of two different airlines of ours, neither Ryanair, may be
-- flown by both, at the pair's one price, the owner's level (manual §2, "Decided, not yet built" until the last of the
-- three pull requests merges). This one adds what the others build on: the joiner's route row, the view of the pairs, the
-- save that joins one, and one fare ladder per pair. Nothing joins until join_pair() exists, and nothing calls it yet but
-- the Scheduling chat (the Join button is pull request 3).
--
-- Adds one column, a check, an index and a trigger on routes, four settings, one view and three functions, and replaces
-- private.fig_fare_ladder() with the same arguments; changes, drops and renames nothing else, so it can be applied from
-- the chat:
--   - routes.shares_route_id: on a joiner's row, the owner's routes row (same world by its foreign key; same two airports
--     and another airline by the trigger), one level only and at most one joiner an owner (a unique index, which is also
--     the foreign key's index). routes' grants and rules are unchanged; planner_save() writes it like any column.
--   - private.check_route_share(): the trigger's check, before a row is added or its pair, airline, world or
--     shares_route_id changes.
--   - settings (every world, airline null): shared_pairs_excluded_airlines (the world's Ryanair, [3] in Gander),
--     shared_pairs_from (the day this runs), shared_pairs_limit (6) and shared_pairs_limit_days (14), the first two
--     Saturdays' limit as data (decision #14).
--   - public.shared_pairs: one row per base-to-base pair of two of our airlines, neither excluded, with its owner, its
--     joiner, their routes and flights a week. security_invoker, select for authenticated only, as flight_legs_local. The
--     country rule that names the owner of a pair neither airline has on its list is a values list in the view (the spec's
--     private.pair_owner(), written as data where the view can read it: a view read as the signed-in user can't call a
--     function in private).
--   - public.join_pair(p_owner_route_id): staff only, as owner, actor-logged (planner when signed in, claude otherwise,
--     detail join_pair): adds the joiner's routes row (or takes up the joiner's own row for the pair), refusing a pair that
--     isn't a shared pair, an excluded airline, a pair that has a joiner, and a seventh pair inside the limit's 14 days.
--   - private.fig_fare_ladder(): on a pair the airline owns with a joiner, each direction and cabin's departures, sold-out
--     share and loads count the joiner's captured flights that way too, and a rotation added on either route holds the
--     pair; the fare index and set-backs stay the airline's own flights (its fares script changes only its own). On a
--     joiner's route, each row shows the pair's level and this week's move on the owner's fare plan (follows), never a
--     move of its own, and lists a set-back to the pair's level for a direction off it. On a shared pair the game's default
--     price is the pair's, read under either airline. fare_ladder() and capture_fare_actions_by_airline() read it,
--     unchanged.

select set_config('equinox.actor', 'migration', true),
       set_config('equinox.actor_detail', '20261105000000_shared_pairs', true);

-- ============================================================ 1. routes: the joiner's row names the owner's
alter table public.routes add column shares_route_id bigint;
alter table public.routes
  add constraint routes_shares_route_fkey foreign key (shares_route_id, world_id) references public.routes (id, world_id),
  add constraint routes_shares_not_itself check (shares_route_id is null or shares_route_id <> id);
create unique index routes_shares_route_id_key on public.routes (shares_route_id);

create or replace function private.check_route_share()
 returns trigger
 language plpgsql
 set search_path to ''
as $function$
declare o record; bad bigint;
begin
  if new.shares_route_id is not null then
    select r.id, r.world_id, r.airline_id, r.hub_code, r.dest_code, r.shares_route_id into o from public.routes r where r.id = new.shares_route_id;
    if not found or o.world_id <> new.world_id or o.airline_id = new.airline_id
       or least(o.hub_code, o.dest_code) <> least(new.hub_code, new.dest_code)
       or greatest(o.hub_code, o.dest_code) <> greatest(new.hub_code, new.dest_code) then
      raise exception 'route %: shares_route_id must name another airline''s route on the same two airports in the same world', coalesce(new.id::text, 'new')
        using errcode = 'check_violation';
    end if;
    if o.shares_route_id is not null then
      raise exception 'route %: route % is a joiner''s route itself (one level of joining only)', coalesce(new.id::text, 'new'), o.id
        using errcode = 'check_violation';
    end if;
    if tg_op = 'UPDATE' and exists (select 1 from public.routes j where j.shares_route_id = new.id) then
      raise exception 'route % has a joiner of its own, so it can''t join another pair', new.id using errcode = 'check_violation';
    end if;
  end if;
  if tg_op = 'UPDATE' then
    select j.id into bad from public.routes j
     where j.shares_route_id = new.id
       and (j.airline_id = new.airline_id or least(j.hub_code, j.dest_code) <> least(new.hub_code, new.dest_code)
            or greatest(j.hub_code, j.dest_code) <> greatest(new.hub_code, new.dest_code))
     limit 1;
    if bad is not null then
      raise exception 'this change to route % would leave its joiner''s route % on another pair or airline', new.id, bad using errcode = 'check_violation';
    end if;
  end if;
  return new;
end
$function$;
revoke all on function private.check_route_share() from public, anon, authenticated, service_role;
create trigger check_route_share before insert or update of shares_route_id, hub_code, dest_code, airline_id, world_id on public.routes
  for each row execute function private.check_route_share();

comment on column public.routes.shares_route_id is 'On a shared pair (manual §2, since 5 Nov; spec docs/specs/2026-11-05-shared-pairs.md §1), the joiner''s row: the owner''s routes row for the same two airports, another airline of ours in the same world (its foreign key and check_route_share). One level only (the owner''s row has none) and one joiner an owner. Null on every other route. Written by join_pair()';
comment on function private.check_route_share() is 'The routes trigger behind shares_route_id (since 5 Nov; spec docs/specs/2026-11-05-shared-pairs.md §1), before a row is added or its shares_route_id, airports, airline or world change: a row that names an owner''s route must be on the same two airports (either way round) and another airline, and the owner''s row must name none (one level of joining); a row with a joiner can''t join another pair, and can''t move to other airports or to the joiner''s airline. Refuses with check_violation.';

-- ============================================================ 2. the settings
insert into public.settings (world_id, airline_id, key, value, unit, description, since, reason)
select w.id, null, x.key, x.value, x.unit, x.description, current_date, x.reason
  from public.worlds w
 cross join lateral (values
   ('shared_pairs_excluded_airlines',
    coalesce((select jsonb_agg(a.id order by a.id) from public.airlines a where a.world_id = w.id and a.planner_name = 'Ryanair'), '[]'::jsonb),
    'airline ids',
    'Our airlines that neither join nor are joined on a shared pair (manual §2, since 5 Nov; spec docs/specs/2026-11-05-shared-pairs.md §1): a list of airline ids, Ryanair''s ([3] in Gander). The shared_pairs view leaves out every pair with a base of one of them, and join_pair() refuses them.',
    'Gitesh, 4 Nov: option B with Ryanair out (brief docs/briefs/2026-11-04-shared-pairs.md)'),
   ('shared_pairs_from', to_jsonb(current_date::text), 'date',
    'The day shared pairs were built (spec docs/specs/2026-11-05-shared-pairs.md §1): the day the migration ran. For shared_pairs_limit_days from it, join_pair() keeps the joined pairs to shared_pairs_limit.',
    'The spec: the build''s date, so the first two Saturdays'' limit counts from it'),
   ('shared_pairs_limit', '6'::jsonb, 'pairs',
    'For the first two Saturdays after the build, at most this many shared pairs have a joiner (manual §2): join_pair() refuses another while shared_pairs_limit_days haven''t passed since shared_pairs_from, so the review can watch the pair ladder.',
    'Gitesh, 4 Nov (brief docs/briefs/2026-11-04-shared-pairs.md): at most 6 pairs until the review has seen the pair ladder'),
   ('shared_pairs_limit_days', '14'::jsonb, 'days',
    'How long the shared-pair limit (shared_pairs_limit) holds, counted from shared_pairs_from: 14, the first two Saturdays after the build (manual §2).',
    'The spec: within 14 days of the build''s date')
 ) x (key, value, unit, description, reason)
on conflict on constraint settings_world_airline_key_key do nothing;

-- ============================================================ 3. the view of the pairs
create view public.shared_pairs with (security_invoker = true) as
with
-- the airlines left out (settings.shared_pairs_excluded_airlines, each world's)
ex as (select s.world_id, (e.v #>> '{}')::bigint as airline_id
         from public.settings s
        cross join lateral jsonb_array_elements(case when jsonb_typeof(s.value) = 'array' then s.value else '[]'::jsonb end) e (v)
        where s.key = 'shared_pairs_excluded_airlines' and s.airline_id is null and jsonb_typeof(e.v) = 'number'),
-- our active airlines' hubs and focus cities (never a station), the excluded left out
bs as (select distinct b.world_id, b.airline_id, b.airport_code
         from public.airline_bases b
         join public.airlines a on a.id = b.airline_id and a.world_id = b.world_id and a.active
         join public.groups g on g.id = a.group_id and g.world_id = a.world_id and g.kind = 'ours'
        where b.role in ('hub', 'focus')
          and not exists (select 1 from ex where ex.world_id = b.world_id and ex.airline_id = b.airline_id)),
-- each pair of two airlines' bases (the lower airline id first), neither airport a base of the other airline
pr as (select x.world_id, x.airline_id as x_al, x.airport_code as x_ap, y.airline_id as y_al, y.airport_code as y_ap
         from bs x
         join bs y on y.world_id = x.world_id and y.airline_id > x.airline_id and y.airport_code <> x.airport_code
        where not exists (select 1 from bs z where z.world_id = x.world_id
                             and ((z.airline_id = x.airline_id and z.airport_code = y.airport_code)
                               or (z.airline_id = y.airline_id and z.airport_code = x.airport_code)))),
-- the country rule (manual §2) as data, for a pair neither airline has on its list: each end as US, GB, IN, CN, MY or
-- EU (any other country of the region Europe), and who owns a pair of them, by the end it names
ru (p, q, owner) as (values ('US', 'IN', 'IN'), ('GB', 'IN', 'IN'), ('US', 'GB', 'US'), ('US', 'EU', 'US'), ('US', 'CN', 'US'),
                            ('GB', 'EU', 'GB'), ('GB', 'CN', 'GB'), ('GB', 'MY', 'GB'), ('EU', 'CN', 'CN'), ('IN', 'CN', 'CN'),
                            ('MY', 'US', 'MY'), ('MY', 'IN', 'MY'), ('MY', 'CN', 'MY'), ('MY', 'EU', 'MY')),
po as (select pr.*, case ru.owner when kx.k then pr.x_al when ky.k then pr.y_al end as rule_owner
         from pr
         left join public.airports ax on ax.code = pr.x_ap
         left join public.countries cx on cx.code = ax.country_code
         left join public.airports ay on ay.code = pr.y_ap
         left join public.countries cy on cy.code = ay.country_code
        cross join lateral (select case when ax.country_code in ('US', 'GB', 'IN', 'CN', 'MY') then ax.country_code when cx.region = 'Europe' then 'EU' end as k) kx
        cross join lateral (select case when ay.country_code in ('US', 'GB', 'IN', 'CN', 'MY') then ay.country_code when cy.region = 'Europe' then 'EU' end as k) ky
         left join ru on (ru.p = kx.k and ru.q = ky.k) or (ru.p = ky.k and ru.q = kx.k)),
-- the owner's row: the airline whose routes row for the pair (from its base) exists, not removed and not a joiner's;
-- were both to have one, the country rule's
orr as (select po.*,
               (select r.id from public.routes r
                 where r.world_id = po.world_id and not r.removed and r.shares_route_id is null
                   and ((r.airline_id = po.x_al and r.hub_code = po.x_ap and r.dest_code = po.y_ap)
                     or (r.airline_id = po.y_al and r.hub_code = po.y_ap and r.dest_code = po.x_ap))
                 order by (r.airline_id is not distinct from po.rule_owner) desc, r.id
                 limit 1) as owner_route_id
          from po),
pa as (select o.*, coalesce(ro.airline_id, o.rule_owner) as owner_al, ro.id as ro_id, ro.airline_id as ro_al, j.id as j_id, j.airline_id as j_al,
              j.created_at as j_created
         from orr o
         left join public.routes ro on ro.id = o.owner_route_id
         left join public.routes j on j.shares_route_id = ro.id and j.world_id = ro.world_id and not j.removed)
select pa.world_id,
       pa.owner_al as owner_airline_id,
       case pa.owner_al when pa.x_al then pa.y_al when pa.y_al then pa.x_al end as joiner_airline_id,
       pa.ro_id as owner_route_id,
       pa.j_id as joiner_route_id,
       case pa.owner_al when pa.x_al then pa.x_ap when pa.y_al then pa.y_ap end as owner_base,
       case pa.owner_al when pa.x_al then pa.y_ap when pa.y_al then pa.x_ap end as joiner_base,
       coalesce((select sum(coalesce(cardinality(l.days_utc), 7)) from public.rotations rt join public.flight_legs l on l.rotation_id = rt.id
                  where rt.route_id = pa.ro_id and rt.airline_id = pa.ro_al), 0)::integer as owner_flights_week,
       coalesce((select sum(coalesce(cardinality(l.days_utc), 7)) from public.rotations rt join public.flight_legs l on l.rotation_id = rt.id
                  where rt.route_id = pa.j_id and rt.airline_id = pa.j_al), 0)::integer as joiner_flights_week,
       (pa.j_created at time zone 'UTC')::date as joined_on
  from pa;

revoke all on table public.shared_pairs from public, anon, authenticated;
grant select on table public.shared_pairs to authenticated;

comment on view public.shared_pairs is 'The shared pairs (manual §2, since 5 Nov; spec docs/specs/2026-11-05-shared-pairs.md §1): one row per pair whose two airports are bases (hub or focus city, never a station) of two different active airlines of ours, neither in settings.shared_pairs_excluded_airlines (Ryanair). Both may fly it at the pair''s one price, the owner''s level. The owner is the airline whose routes row for the pair (from its base, not removed, not a joiner''s) exists; for a pair neither has on its list, the country rule''s airline (US/UK–India Kingfisher, US–UK/Europe/China Pan Am, UK–Europe/China/Malaysia Virgin, Europe/India–China China Eastern, Malaysia Malaysia, as a values list in the view). The joiner is the other airline; its route (routes.shares_route_id naming the owner''s) is null until it joins (join_pair()). Flights a week count both legs of each route''s rotations (flight_legs, every weekday when none are set). Shows the caller only what it may read.';
comment on column public.shared_pairs.world_id is 'The pair''s world';
comment on column public.shared_pairs.owner_airline_id is 'The owner: the airline whose routes row for the pair exists, else the country rule''s (manual §2); its level is the pair''s';
comment on column public.shared_pairs.joiner_airline_id is 'The other airline of the pair, which may join it (join_pair()) and then follows the owner''s fare ladder';
comment on column public.shared_pairs.owner_route_id is 'The owner''s routes row for the pair; null when neither airline has it on its list';
comment on column public.shared_pairs.joiner_route_id is 'The joiner''s routes row (shares_route_id naming the owner''s); null until the pair is joined';
comment on column public.shared_pairs.owner_base is 'The owner''s end of the pair: its hub or focus city';
comment on column public.shared_pairs.joiner_base is 'The joiner''s end of the pair: its hub or focus city';
comment on column public.shared_pairs.owner_flights_week is 'The owner''s flights a week on the pair, both ways (flight_legs of its route''s rotations)';
comment on column public.shared_pairs.joiner_flights_week is 'The joiner''s flights a week on the pair, both ways; 0 until it flies it';
comment on column public.shared_pairs.joined_on is 'The day the joiner''s routes row was added (its created_at, UTC); null until the pair is joined';

-- ============================================================ 4. joining a pair
create or replace function public.join_pair(p_owner_route_id bigint)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_actor text := current_setting('equinox.actor', true);
  v_detail text := current_setting('equinox.actor_detail', true);
  o record; j record;
  v_joiner bigint; v_joiner_base text; v_owner_base text; v_ex jsonb; v_names text;
  v_from date; v_limit numeric; v_days numeric; v_joined int; v_id bigint; v_reused boolean := false;
begin
  if not private.caller_is_staff() then raise exception 'only planner staff can join a pair' using errcode = '42501'; end if;
  select r.* into o from public.routes r where r.id = p_owner_route_id;
  if not found then raise exception 'join_pair: there is no route %', coalesce(p_owner_route_id::text, 'null') using errcode = '22023'; end if;
  -- saves of the planner take the same lock (planner_save()), so two joins can't both pass the limit
  perform pg_advisory_xact_lock(hashtextextended('equinox planner world', o.world_id));
  if o.removed then raise exception 'join_pair: route % (%–%) is removed', o.id, o.hub_code, o.dest_code using errcode = '22023'; end if;
  if o.shares_route_id is not null then
    raise exception 'join_pair: route % (%–%) is a joiner''s route; join the owner''s, route %', o.id, o.hub_code, o.dest_code, o.shares_route_id using errcode = '22023';
  end if;
  -- a shared pair (manual §2): the route's airline has a hub or focus city at one end and another active airline of ours
  -- at the other (a station is never a base)
  select b.airline_id, b.airport_code into v_joiner, v_joiner_base
    from public.airline_bases b
    join public.airlines a on a.id = b.airline_id and a.world_id = b.world_id and a.active
    join public.groups g on g.id = a.group_id and g.world_id = a.world_id and g.kind = 'ours'
   where b.world_id = o.world_id and b.role in ('hub', 'focus') and b.airport_code in (o.hub_code, o.dest_code) and b.airline_id <> o.airline_id
   order by b.airport_code = o.dest_code desc, b.airline_id
   limit 1;
  if v_joiner is null then
    raise exception 'join_pair: %–% isn''t a shared pair: neither airport is a hub or focus city of another of our airlines', o.hub_code, o.dest_code
      using errcode = '22023';
  end if;
  v_owner_base := case when v_joiner_base = o.dest_code then o.hub_code else o.dest_code end;
  if not exists (select 1 from public.airline_bases b where b.world_id = o.world_id and b.airline_id = o.airline_id
                    and b.airport_code = v_owner_base and b.role in ('hub', 'focus')) then
    raise exception 'join_pair: %–% isn''t a shared pair: % isn''t a hub or focus city of the route''s airline', o.hub_code, o.dest_code, v_owner_base
      using errcode = '22023';
  end if;
  select s.value into v_ex from public.settings s where s.world_id = o.world_id and s.airline_id is null and s.key = 'shared_pairs_excluded_airlines';
  if jsonb_typeof(v_ex) = 'array' and (v_ex @> to_jsonb(o.airline_id) or v_ex @> to_jsonb(v_joiner)) then
    select string_agg(coalesce(a.public_name, a.planner_name, a.game_name), ' and ' order by a.id) into v_names
      from public.airlines a where a.id in (o.airline_id, v_joiner) and v_ex @> to_jsonb(a.id);
    raise exception 'join_pair: % neither joins nor is joined on a shared pair (settings.shared_pairs_excluded_airlines)', v_names using errcode = '22023';
  end if;
  select r.id into v_id from public.routes r where r.shares_route_id = o.id;
  if v_id is not null then
    raise exception 'join_pair: %–% has a joiner already (route %)', o.hub_code, o.dest_code, v_id using errcode = '22023';
  end if;
  -- the first two Saturdays' limit (manual §2): shared_pairs_limit pairs while shared_pairs_limit_days haven't passed
  -- since shared_pairs_from (with no date, the limit holds)
  select (s.value #>> '{}')::date into v_from from public.settings s
   where s.world_id = o.world_id and s.airline_id is null and s.key = 'shared_pairs_from' and jsonb_typeof(s.value) = 'string';
  v_limit := private.fig_num(o.world_id, null, 'shared_pairs_limit');
  v_days := private.fig_num(o.world_id, null, 'shared_pairs_limit_days');
  select count(*)::int into v_joined from public.routes r where r.world_id = o.world_id and r.shares_route_id is not null and not r.removed;
  if (v_from is null or current_date - v_from < v_days) and v_joined >= v_limit then
    raise exception 'join_pair: % pairs are joined already, the most until %', v_joined,
      coalesce(to_char(v_from + v_days::int, 'FMDD Mon YYYY'), 'shared_pairs_from is set') using errcode = '22023';
  end if;
  -- the joiner's own row for the pair, from its base, if it has one (its research list's): taken up rather than doubled.
  -- One the other way round can't be
  if exists (select 1 from public.routes r where r.airline_id = v_joiner and r.hub_code = v_owner_base and r.dest_code = v_joiner_base) then
    raise exception 'join_pair: the joiner has %–% on its list the other way round; correct that row first', v_owner_base, v_joiner_base using errcode = '22023';
  end if;
  select r.* into j from public.routes r where r.airline_id = v_joiner and r.hub_code = v_joiner_base and r.dest_code = v_owner_base;

  perform set_config('equinox.actor', coalesce(nullif(v_actor, ''), case when auth.uid() is not null then 'planner' else 'claude' end), true),
          set_config('equinox.actor_detail', 'join_pair', true);
  if j.id is not null then
    update public.routes r
       set shares_route_id = o.id, removed = false, removed_note = null,
           stars = o.stars, stars_override = o.stars_override, market_id = o.market_id, market_override_id = o.market_override_id,
           market_cleared = o.market_cleared, distance_km = o.distance_km, distance_override_km = o.distance_override_km, cabin_choice = o.cabin_choice
     where r.id = j.id
     returning r.id into v_id;
    v_reused := true;
  else
    insert into public.routes (world_id, airline_id, hub_code, dest_code, city, country_label, distance_km, distance_override_km, market_id,
                               market_override_id, market_cleared, stars, stars_override, cabin_choice, source, shares_route_id)
    select o.world_id, v_joiner, v_joiner_base, v_owner_base, ap.city, ap.country_code, o.distance_km, o.distance_override_km, o.market_id,
           o.market_override_id, o.market_cleared, o.stars, o.stars_override, o.cabin_choice, 'added', o.id
      from (select 1) one left join public.airports ap on ap.code = v_owner_base
    returning id into v_id;
  end if;
  perform set_config('equinox.actor', coalesce(v_actor, ''), true), set_config('equinox.actor_detail', coalesce(v_detail, ''), true);
  return jsonb_build_object('ok', true, 'route_id', v_id, 'reused', v_reused, 'owner_route_id', o.id, 'owner_airline_id', o.airline_id,
                            'joiner_airline_id', v_joiner, 'hub', v_joiner_base, 'dest', v_owner_base, 'joined', v_joined + 1,
                            'limit', case when v_from is null or current_date - v_from < v_days
                                          then jsonb_build_object('pairs', v_limit, 'until', v_from + v_days::int) end);
end
$function$;
revoke all on function public.join_pair(bigint) from public, anon, authenticated, service_role;
grant execute on function public.join_pair(bigint) to authenticated;

comment on function public.join_pair(bigint) is 'Joins a shared pair (manual §2, since 5 Nov; spec docs/specs/2026-11-05-shared-pairs.md §1): p_owner_route_id is the owner''s routes row; adds the joiner''s row for the other base''s airline, from its base to the owner''s (source added, city and country from the owner''s airport), copying stars, stars_override, the market (market_id, market_override_id, market_cleared), the distance (distance_km, distance_override_km) and cabin_choice from the owner''s, with shares_route_id set; where the joiner already has the pair on its list from its base, that row is taken up instead (restored if removed, the same columns copied). Refused (22023, saying why) when the route isn''t there, is removed or is a joiner''s; when the pair isn''t a shared pair (both airports hubs or focus cities, never stations, of the route''s airline and of another active airline of ours); when either airline is in settings.shared_pairs_excluded_airlines (Ryanair); when the pair has a joiner; when the joiner has the pair the other way round; and when shared_pairs_limit pairs (6) are joined and shared_pairs_limit_days (14) haven''t passed since shared_pairs_from (the first two Saturdays). Answers ok, route_id, reused, owner_route_id, owner_airline_id, joiner_airline_id, hub, dest, joined (the pairs joined now) and limit (pairs and until, while it holds). Staff only (signed in, or postgres for the Scheduling chat); runs as owner with an empty search path and the planner''s save lock; the change log names actor planner when signed in, else claude unless the caller named one, with detail join_pair. The Routes screen''s and the route page''s Join this pair button call it (pull request 3).';

-- ============================================================ 5. the fare ladder: one ladder per shared pair
CREATE OR REPLACE FUNCTION private.fig_fare_ladder(p_airline_id bigint, p_as_of timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare
  w bigint := private.fig_airline_world(p_airline_id);
  v_today date := (p_as_of at time zone 'UTC')::date;
  v_week date;
  v_step numeric; v_up numeric; v_down numeric; v_min numeric; v_hold numeric; v_up_hold numeric; v_cap numeric; v_launch numeric; v_floor numeric;
  v_new_days numeric; v_added_days numeric;
  -- every route was at its launch level on 21 Oct 2026 (Gitesh; manual §5): each route's fare that day is its baseline
  v_base_day constant date := date '2026-10-21';
  v_scan bigint; v_scan_at timestamptz;
  v_rows jsonb; v_actions jsonb := '[]'::jsonb; v_n int := 0;
  v_r record; v_sets jsonb; v_change jsonb; v_lv numeric; v_words text;
  -- the fare ladder under launch (since 23 Oct; spec docs/specs/2026-10-23-fare-ladder-under-launch.md; judged by loads
  -- since 26 Oct, spec docs/specs/2026-10-26-under-launch-by-loads.md)
  v_ul_load numeric; v_ul_days numeric; v_ul_min numeric; v_ul_levels numeric[]; v_ul_below numeric[]; v_ul_j jsonb; v_ul_span text;
  -- shared pairs (since 5 Nov; spec docs/specs/2026-11-05-shared-pairs.md §2): the airlines whose captured flights this
  -- ladder reads, the airline's own and, on a pair it owns with a joiner, the joiner's
  v_ids bigint[];
begin
  v_step := private.fig_num(w, p_airline_id, 'fare_ladder_step_pts');
  v_up := private.fig_num(w, p_airline_id, 'fare_ladder_up_share');
  v_down := private.fig_num(w, p_airline_id, 'fare_ladder_down_share');
  v_min := private.fig_num(w, p_airline_id, 'fare_ladder_min_departures');
  v_hold := private.fig_num(w, p_airline_id, 'fare_ladder_hold_weeks');
  -- the hold after a step up (since 26 Oct, manual §5): bookings open 3 days ahead (§9), so the week after a change mostly
  -- flies at the old price
  v_up_hold := private.fig_num(w, p_airline_id, 'fare_ladder_up_hold_weeks');
  v_cap := private.fig_num(w, p_airline_id, 'fare_ladder_cap_pts');
  v_launch := private.fig_num(w, p_airline_id, 'fare_launch_pct');
  v_new_days := private.fig_num(w, p_airline_id, 'growth_new_route_days');
  v_added_days := private.fig_num(w, p_airline_id, 'fare_ladder_capacity_hold_days');
  select (r.value #>> '{}')::numeric into v_floor from public.world_rules r where r.world_id = w and r.key = 'fare_floor_pct';
  -- under launch: a cabin at launch averaging under fare_under_launch_load_pct full over fare_under_launch_days jumps to
  -- the first of fare_under_launch_levels, holds that many days and is then judged on its loads like any direction (since
  -- 26 Oct; fare_under_launch_decide_load_pct is no longer read). An airline's own row wins over the world's, as fig_num()
  -- reads them
  v_ul_load := private.fig_num(w, p_airline_id, 'fare_under_launch_load_pct');
  v_ul_days := private.fig_num(w, p_airline_id, 'fare_under_launch_days');
  v_ul_min := private.fig_num(w, p_airline_id, 'fare_under_launch_min_flights');
  select s.value into v_ul_j from public.settings s
   where s.world_id = w and s.key = 'fare_under_launch_levels' and (s.airline_id is null or s.airline_id = p_airline_id)
   order by s.airline_id nulls last limit 1;
  if v_ul_j is null or jsonb_typeof(v_ul_j) <> 'array'
     or exists (select 1 from jsonb_array_elements(v_ul_j) e where jsonb_typeof(e) <> 'number') then
    raise exception 'setting fare_under_launch_levels is missing or isn''t a list of numbers' using errcode = '22023';
  end if;
  select array_agg((e #>> '{}')::numeric order by i) into v_ul_levels from jsonb_array_elements(v_ul_j) with ordinality as t(e, i);
  v_ul_span := case when v_ul_days > 0 and v_ul_days % 7 = 0
                    then format('%s week%s', trim_scale(v_ul_days / 7), case when v_ul_days = 7 then '' else 's' end)
                    else format('%s days', trim_scale(v_ul_days)) end;
  -- the jump levels under this airline's launch, in order (a level at or above launch is never a jump)
  select array_agg(u.l order by u.i) into v_ul_below from unnest(v_ul_levels) with ordinality as u(l, i) where u.l < v_launch;
  -- this Saturday: the latest Saturday on or before the moment's UTC date. A move recorded on the fare plan since then is
  -- this week's (on the fare plan already); the levels before it are the ones the week's move starts from
  v_week := v_today - ((extract(isodow from v_today)::int + 1) % 7);
  -- the latest finished world scan by then with its schedules: who else flies each pair (the 60% floor)
  -- the joiners of the airline's shared pairs (routes.shares_route_id naming one of its routes): the owner's ladder judges
  -- each such pair on both airlines' captured flights (spec §2)
  select array[p_airline_id] || coalesce(array_agg(distinct j.airline_id), '{}') into v_ids
    from public.routes o join public.routes j on j.shares_route_id = o.id and j.world_id = o.world_id and not j.removed
   where o.airline_id = p_airline_id and o.world_id = w and not o.removed;
  select s.id, s.taken_at into v_scan, v_scan_at from public.game_scans s
   where s.world_id = w and s.status = 'done' and s.taken_at <= p_as_of
     and exists (select 1 from public.game_scan_schedules x where x.scan_id = s.id)
   order by s.taken_at desc, s.id desc limit 1;

  with
  ro as (select r.id, r.hub_code, r.dest_code, r.shares_route_id from public.routes r where r.airline_id = p_airline_id and r.world_id = w and not r.removed),
  -- shared pairs (since 5 Nov; spec docs/specs/2026-11-05-shared-pairs.md §2): each of the airline's routes on a joined pair
  -- with the other airline's route and the airline's role on it. As owner: the joiner's route (shares_route_id naming
  -- ours). As joiner: the owner's route, with the owner's launch level, step and cap (its settings rows), its name
  pm as materialized (
    select ro.id as route_id, 'owner'::text as role, j.id as p_route, j.airline_id as p_airline, j.hub_code as p_hub, j.dest_code as p_dest,
           null::numeric as p_launch, null::numeric as p_step, null::numeric as p_cap,
           coalesce(pa.public_name, pa.planner_name, pa.game_name) as p_name
      from ro join public.routes j on j.shares_route_id = ro.id and j.world_id = w and not j.removed
      join public.airlines pa on pa.id = j.airline_id
    union all
    select ro.id, 'joiner', o.id, o.airline_id, o.hub_code, o.dest_code,
           private.fig_num(w, o.airline_id, 'fare_launch_pct'), private.fig_num(w, o.airline_id, 'fare_ladder_step_pts'),
           private.fig_num(w, o.airline_id, 'fare_ladder_cap_pts'), coalesce(pa.public_name, pa.planner_name, pa.game_name)
      from ro join public.routes o on o.id = ro.shares_route_id and o.world_id = w and not o.removed
      join public.airlines pa on pa.id = o.airline_id),
  fq as materialized (select * from private.fig_freqs(w, p_airline_id)),
  -- a route's age: its earliest rotation's launch day, as route profit has it (growth_new_route_days)
  age as (select f.route_id, min(f.launched_on) as first_day from fq f group by f.route_id),
  -- its newest live rotation's launch day: a flight added to a route already flown (manual §5, since 21 Oct)
  added as (select f.route_id, max(f.launched_on) as last_day from fq f where f.live group by f.route_id),
  -- on a pair the airline owns, the joiner's newest rotation: a frequency added by either airline holds the pair (spec §2)
  padd as (select pm.route_id, max(rt.launched_on) as last_day
             from pm join public.rotations rt on rt.route_id = pm.p_route and rt.airline_id = pm.p_airline
            where pm.role = 'owner' group by pm.route_id),
  -- business seats on an aircraft flying one of the route's rotations
  biz as (select distinct f.route_id from fq f
            join public.flight_legs fl on fl.rotation_id = f.rotation_id
            join public.aircraft a on a.id = fl.aircraft_id
            join public.cabin_configs cc on cc.id = a.cabin_config_id
           where f.live and coalesce(cc.business_seats, 0) > 0),
  -- every captured loads row of the airline by then (one per date and flight number, the latest), with its route as the
  -- airline's list has it, either way round (as route profit matches them: route_id is often empty), and since 26 Oct its
  -- direction: out from the route's hub, back to it. Since 5 Nov (spec docs/specs/2026-11-05-shared-pairs.md §2) also, on a
  -- pair the airline owns with a joiner, the joiner's flights on it, matched to the owner's route by their airports (own
  -- false): the week's departures, sold-out share and loads are the pair's; the fare index, the set-back and the baseline
  -- stay the airline's own flights, since its fares script changes only its own
  lf as materialized (
    select coalesce(r1.id, r2.id) as route_id, case when r1.id is not null then 'out' else 'back' end as dir, x.al = p_airline_id as own, x.*
      from (select distinct on (f.airline_id, f.game_date, f.flight_no) f.airline_id as al, f.game_date, f.origin_code as o, f.dest_code as d, f.dep_at,
                   f.eco_pct, f.eco_fare, f.bus_pct, f.bus_seats, f.bus_fare
              from public.game_flights f
             where f.airline_id = any (v_ids) and f.flight_no is not null and f.loads_captured_at <= p_as_of and f.game_date <= v_today
             order by f.airline_id, f.game_date, f.flight_no, f.id desc) x
      left join ro r1 on r1.hub_code = x.o and r1.dest_code = x.d
                     and (x.al = p_airline_id or exists (select 1 from pm where pm.route_id = r1.id and pm.role = 'owner' and pm.p_airline = x.al))
      left join ro r2 on r2.hub_code = x.d and r2.dest_code = x.o
                     and (x.al = p_airline_id or exists (select 1 from pm where pm.route_id = r2.id and pm.role = 'owner' and pm.p_airline = x.al))
     where coalesce(r1.id, r2.id) is not null),
  -- by cabin: economy on every row with its load, business on flights with business seats; each with its direction (o)
  lc as materialized (
    select lf.route_id, 'economy'::text as cabin, lf.dir, lf.o, lf.game_date, lf.dep_at, lf.eco_pct as pct, lf.eco_fare as fare,
           coalesce(lf.dep_at, lf.game_date::timestamp at time zone 'UTC') as at, lf.own from lf where lf.eco_pct is not null
    union all
    select lf.route_id, 'business', lf.dir, lf.o, lf.game_date, lf.dep_at, lf.bus_pct, lf.bus_fare,
           coalesce(lf.dep_at, lf.game_date::timestamp at time zone 'UTC'), lf.own from lf where lf.bus_pct is not null and coalesce(lf.bus_seats, 0) > 0),
  -- the 7 days before the moment, by scheduled departure (the departure date where it isn't known), per direction since
  -- 26 Oct, with the direction's average load in the cabin
  st as (select lc.route_id, lc.cabin, lc.dir, count(*)::int as n, (count(*) filter (where lc.pct >= 100))::int as sold, avg(lc.fare) as fare,
                avg(lc.pct) as load
           from lc
          where lc.at >= p_as_of - interval '7 days' and lc.at < p_as_of
          group by lc.route_id, lc.cabin, lc.dir),
  -- the fare index's baseline (manual §5, since 21 Oct). Each captured day's fare by cabin and direction: the flights'
  -- lowest (one the game priced otherwise, as a new flight at the default price on a Ryanair route, sits above it), else
  -- the daily history's average fare in that cabin (route_days, kept for good once the flights are archived): economy's,
  -- and since 22 Oct business's, on a day with business passengers
  dd as (select lc.route_id, lc.cabin, lc.o, lc.game_date as day, min(lc.fare) as fare from lc where lc.fare > 0 and lc.own group by 1, 2, 3, 4),
  hd as (select coalesce(r1.id, r2.id) as route_id, c.cabin, d.origin_code as o, d.day, avg(c.fare) as fare
           from public.route_days d
           left join ro r1 on r1.hub_code = d.origin_code and r1.dest_code = d.dest_code
           left join ro r2 on r2.hub_code = d.dest_code and r2.dest_code = d.origin_code
           cross join lateral (values ('economy'::text, case when d.eco_fare_avg > 0 then d.eco_fare_avg end),
                                      ('business'::text, case when d.bus_pax > 0 and d.bus_fare_avg > 0 then d.bus_fare_avg end)) c (cabin, fare)
          where d.airline_id = p_airline_id and c.fare is not null and d.day <= v_today and coalesce(r1.id, r2.id) is not null
          group by 1, 2, 3, 4),
  bd as materialized (
    select coalesce(dd.route_id, hd.route_id) as route_id, coalesce(dd.cabin, hd.cabin) as cabin, coalesce(dd.o, hd.o) as o,
           coalesce(dd.day, hd.day) as day, coalesce(dd.fare, hd.fare) as fare
      from dd full join hd on hd.route_id = dd.route_id and hd.cabin = dd.cabin and hd.o = dd.o and hd.day = dd.day),
  -- each direction's baseline day: the latest on or before 21 Oct 2026, when every route was at its launch level; for a
  -- route launched later, its first captured day, if within the route's first growth_new_route_days days (later than
  -- that, the first fare kept may not be at launch: the days before it archived)
  bk as (select bd.route_id, bd.cabin, bd.o, max(bd.day) filter (where bd.day <= v_base_day) as on_day, min(bd.day) as first_seen
           from bd group by 1, 2, 3),
  base as (select bk.route_id, bk.cabin, bk.o, bd.day, bd.fare
             from bk
             left join age ag on ag.route_id = bk.route_id
             join bd on bd.route_id = bk.route_id and bd.cabin = bk.cabin and bd.o = bk.o
                    and bd.day = coalesce(bk.on_day, case when ag.first_day is not null and bk.first_seen - ag.first_day < v_new_days then bk.first_seen end)),
  -- each direction's baseline (since 26 Oct a row each: out from the route's hub, back to it)
  bs as (select base.route_id, base.cabin, case when base.o = ro.hub_code then 'out' else 'back' end as dir, avg(base.fare) as fare, max(base.day) as day
           from base join ro on ro.id = base.route_id group by 1, 2, 3),
  -- since 4 Nov (spec docs/specs/2026-11-04-fare-default-from-market.md §3): the game's default price for each direction
  -- and cabin, from the latest finished market run that read it with our airline open (private.fig_default_prices():
  -- economy Y, business C). Where there is one, a direction's captured fares are measured against it (×100); elsewhere
  -- against the inferred baseline above, times the launch level, as before
  -- Since 5 Nov, on a shared pair, the other airline's reading too: the market pages read a pair two of our airlines fly
  -- once, under one of them, and the game's default is the pair's, whoever flies it; the latest run's wins, ours on a tie
  dpx as (select d.route_id, d.cabin, d.direction as dir, d.default_price, d.run_on, 0 as pri
            from private.fig_default_prices(p_airline_id, p_as_of) d
          union all
          select pm.route_id, d.cabin, case when d.origin = ro.hub_code then 'out' else 'back' end, d.default_price, d.run_on, 1
            from (select distinct pm.p_airline from pm) pa
           cross join lateral private.fig_default_prices(pa.p_airline, p_as_of) d
            join pm on pm.p_airline = pa.p_airline and pm.p_route = d.route_id
            join ro on ro.id = pm.route_id),
  dp as materialized (select distinct on (x.route_id, x.cabin, x.dir) x.route_id, x.cabin, x.dir, x.default_price, x.run_on
                        from dpx x order by x.route_id, x.cabin, x.dir, x.run_on desc, x.pri),
  eb as (select coalesce(dp.route_id, bs.route_id) as route_id, coalesce(dp.cabin, bs.cabin) as cabin, coalesce(dp.dir, bs.dir) as dir,
                coalesce(dp.default_price, bs.fare) as fare,
                case when dp.default_price is not null then 100 else v_launch end as scale,
                case when dp.default_price is not null then 'market' else 'inferred' end as source,
                case when dp.default_price is not null then dp.run_on else bs.day end as day,
                dp.run_on as default_on
           from dp full join bs on bs.route_id = dp.route_id and bs.cabin = dp.cabin and bs.dir = dp.dir),
  -- the latest captured day by cabin and direction: its average fare, and each flight's fare as a % of the default price:
  -- against the direction's default where the market pages read it, else against its inferred baseline times the launch
  -- level (since 4 Nov); and, to compare, against the inferred baseline always (inf)
  lday as (select lc.route_id, lc.cabin, lc.dir, max(lc.game_date) as day from lc where lc.fare > 0 and lc.own group by 1, 2, 3),
  latest as (select ld.route_id, ld.cabin, ld.dir, ld.day, avg(lc.fare) as fare,
                    array_agg(lc.fare / e.fare * e.scale order by lc.dep_at) filter (where e.fare > 0) as ratios,
                    array_agg(lc.fare / b.fare * v_launch order by lc.dep_at) filter (where b.fare > 0) as inf
               from lday ld
               join lc on lc.route_id = ld.route_id and lc.cabin = ld.cabin and lc.dir = ld.dir and lc.game_date = ld.day and lc.fare > 0 and lc.own
               left join eb e on e.route_id = lc.route_id and e.cabin = lc.cabin and e.dir = lc.dir
               left join bs b on b.route_id = lc.route_id and b.cabin = lc.cabin and b.dir = lc.dir
              group by ld.route_id, ld.cabin, ld.dir, ld.day),
  -- the levels the fare plan recorded (manual §5): before this Saturday, the latest is the level; since it, this week's move.
  -- Since 26 Oct per direction: a row with a direction counts for that direction, a both-directions row (direction null,
  -- every row written before then) for each of them, so a direction's level is its own latest row, or the latest
  -- both-directions row if that is later (proposed on, then id)
  rec as (select fp.id, fp.route_id, coalesce(fp.cabin_class, 'economy') as cabin, d.dir, fp.direction, fp.level_pct, fp.ladder_move,
                 fp.proposed_on, fp.reason, fp.fare_from, fp.change_pct
            from public.fare_plan fp
           cross join (values ('out'), ('back')) d (dir)
           where fp.airline_id = p_airline_id and fp.world_id = w and fp.level_pct is not null and fp.status <> 'dropped'
             and fp.proposed_on <= v_today and (fp.direction is null or fp.direction = d.dir)),
  prev as (select distinct on (r.route_id, r.cabin, r.dir) r.* from rec r where r.proposed_on < v_week
            order by r.route_id, r.cabin, r.dir, r.proposed_on desc, r.id desc),
  wk as (select distinct on (r.route_id, r.cabin, r.dir) r.* from rec r where r.proposed_on >= v_week
          order by r.route_id, r.cabin, r.dir, r.proposed_on desc, r.id desc),
  dn as (select r.route_id, r.cabin, r.dir, max(r.proposed_on) as down_on from rec r where r.ladder_move = 'down' and r.proposed_on < v_week group by 1, 2, 3),
  -- the latest step up before this Saturday (since 26 Oct, manual §5), a both-directions row counting for both as above.
  -- Only up: a jump and a set-back never start this hold (nor a revert, recorded before 26 Oct)
  upr as (select r.route_id, r.cabin, r.dir, max(r.proposed_on) as up_on from rec r where r.ladder_move = 'up' and r.proposed_on < v_week group by 1, 2, 3),
  -- shared pairs (since 5 Nov; spec §2): a joiner's directions follow the pair's level, the owner's, read from the owner's
  -- fare plan rows as the owner's ladder reads its own (before this Saturday the latest; since it this week's move), each
  -- in the joiner's own direction: the one leaving the same airport
  orec as (select fp.id, pm.route_id, coalesce(fp.cabin_class, 'economy') as cabin,
                  case when (case d.dir when 'out' then pm.p_hub else pm.p_dest end) = ro.hub_code then 'out' else 'back' end as dir,
                  fp.level_pct, fp.ladder_move, fp.proposed_on
             from pm
             join ro on ro.id = pm.route_id
             join public.fare_plan fp on fp.route_id = pm.p_route and fp.airline_id = pm.p_airline and fp.world_id = w
            cross join (values ('out'), ('back')) d (dir)
            where pm.role = 'joiner' and fp.level_pct is not null and fp.status <> 'dropped' and fp.proposed_on <= v_today
              and (fp.direction is null or fp.direction = d.dir)),
  oprev as (select distinct on (r.route_id, r.cabin, r.dir) r.* from orec r where r.proposed_on < v_week
             order by r.route_id, r.cabin, r.dir, r.proposed_on desc, r.id desc),
  owk as (select distinct on (r.route_id, r.cabin, r.dir) r.* from orec r where r.proposed_on >= v_week
           order by r.route_id, r.cabin, r.dir, r.proposed_on desc, r.id desc),
  -- under launch (since 23 Oct; spec docs/specs/2026-10-23-fare-ladder-under-launch.md §2), per direction since 26 Oct,
  -- judged by loads since 26 Oct (spec docs/specs/2026-10-26-under-launch-by-loads.md). Each cabin's day by day fare, each
  -- direction's and both directions' together (dir 'both', for a both-directions row), and its jumps recorded before this
  -- Saturday, each with the day it took effect: the first captured day on or after it was proposed whose fare (the row's
  -- direction's, or both directions' for a both-directions row) is the fare then times its ratio, within 1%
  -- (fare_plan_status()'s rule, read over every captured day, so the day holds once the flights are older than its 10
  -- days), else the day proposed
  cday as materialized (select lc.route_id, lc.cabin, coalesce(lc.dir, 'both') as dir, lc.game_date as day, avg(lc.fare) as fare
                          from lc where lc.fare > 0 and lc.own group by grouping sets ((lc.route_id, lc.cabin, lc.dir, lc.game_date), (lc.route_id, lc.cabin, lc.game_date))),
  jr as (select r.id, r.route_id, r.cabin, r.dir, r.level_pct, r.proposed_on,
                coalesce((select min(c.day) from cday c
                           where c.route_id = r.route_id and c.cabin = r.cabin and c.dir = coalesce(r.direction, 'both') and c.day >= r.proposed_on and r.fare_from > 0
                             and abs(c.fare / r.fare_from - (1 + coalesce(r.change_pct, 0) / 100)) <= 0.01), r.proposed_on) as on_day
           from rec r where r.ladder_move = 'jump' and r.proposed_on < v_week),
  jl as (select distinct on (jr.route_id, jr.cabin, jr.dir) jr.route_id, jr.cabin, jr.dir, jr.id, jr.proposed_on, jr.on_day as jumped_on
           from jr order by jr.route_id, jr.cabin, jr.dir, jr.proposed_on desc, jr.id desc),
  -- done: a step recorded after the latest jump (it climbed: under launch the ladder then only climbs or holds, and never
  -- jumps again), or a revert recorded before 26 Oct (back at launch): no more jumps for that cabin and direction. A hold
  -- row doesn't end it (since 26 Oct)
  ud as (select jl.route_id, jl.cabin, jl.dir from jl
          where exists (select 1 from rec r where r.route_id = jl.route_id and r.cabin = jl.cabin and r.dir = jl.dir and r.proposed_on < v_week
                           and (r.ladder_move = 'revert' or (r.ladder_move in ('up', 'down') and (r.proposed_on, r.id) > (jl.proposed_on, jl.id))))),
  -- marked: a hold recorded after the latest jump (since 26 Oct the cut-or-keep mark, put on the fare plan the first
  -- Saturday a cabin at the last jump level is judged under fare_ladder_down_share sold out; before then the judgement
  -- that a jump paid): at the last level the cabin stays marked until it climbs
  um as (select jl.route_id, jl.cabin, jl.dir from jl
          where exists (select 1 from rec r where r.route_id = jl.route_id and r.cabin = jl.cabin and r.dir = jl.dir and r.proposed_on < v_week
                           and r.ladder_move = 'hold' and (r.proposed_on, r.id) > (jl.proposed_on, jl.id))),
  -- the latest recorded level change (any row but a hold): at launch, the window must be all at that level
  lch as (select r.route_id, r.cabin, r.dir, max(r.proposed_on) as changed_on from rec r where r.ladder_move is distinct from 'hold' group by 1, 2, 3),
  -- the window at launch: the fare_under_launch_days before the moment, by scheduled departure, the direction's flights
  uw as (select lc.route_id, lc.cabin, lc.dir, count(*)::int as n, avg(lc.pct) as load
           from lc where lc.at >= p_as_of - make_interval(days => v_ul_days::int) and lc.at < p_as_of group by 1, 2, 3),
  -- at the jump level: the direction's flights since the latest jump took effect, to the moment (shown, not judged on)
  uj as (select lc.route_id, lc.cabin, lc.dir, count(*)::int as n, avg(lc.pct) as load
           from lc join jl on jl.route_id = lc.route_id and jl.cabin = lc.cabin and jl.dir = lc.dir
          where lc.at >= jl.jumped_on::timestamp at time zone 'UTC' and lc.at < p_as_of
          group by 1, 2, 3),
  -- the window a cabin due at a jump level is judged on (since 2 Nov, manual §5): the fare_under_launch_days before the
  -- moment, none before the jump took effect; under fare_under_launch_load_pct full it may jump again
  ujw as (select lc.route_id, lc.cabin, lc.dir, count(*)::int as n, avg(lc.pct) as load
            from lc join jl on jl.route_id = lc.route_id and jl.cabin = lc.cabin and jl.dir = lc.dir
           where lc.at >= greatest(jl.jumped_on::timestamp at time zone 'UTC', p_as_of - make_interval(days => v_ul_days::int)) and lc.at < p_as_of
           group by 1, 2, 3),
  -- whether the captures show this week's move yet (fare_plan_status()'s rule)
  seen as (select (e ->> 'id')::bigint as id, (e ->> 'applied')::boolean as applied, (e ->> 'seen_on')::date as seen_on
             from jsonb_array_elements(case when exists (select 1 from wk) then private.fig_fare_plan(p_airline_id, p_as_of) -> 'plan' else '[]'::jsonb end) e),
  -- another player on the pair, either way round (our own airlines included, manual §9): the latest scan, and our other
  -- airlines' own flights
  pairs as (select distinct least(ro.hub_code, ro.dest_code) as a, greatest(ro.hub_code, ro.dest_code) as b from ro),
  other as (select least(f ->> 2, f ->> 3) as a, greatest(f ->> 2, f ->> 3) as b
              from public.game_scan_schedules sc
              cross join lateral jsonb_array_elements(case when jsonb_typeof(sc.flights) = 'array' then sc.flights else '[]'::jsonb end) f
             where sc.scan_id = v_scan and sc.airline_id <> p_airline_id and jsonb_typeof(f) = 'array'
            union
            select least(l.origin_code, l.dest_code), greatest(l.origin_code, l.dest_code)
              from public.flight_legs l where l.world_id = w and l.airline_id <> p_airline_id),
  contested as (select p.a, p.b from pairs p where exists (select 1 from other o where o.a = p.a and o.b = p.b)),
  -- a rival that started on the pair, or added competition_threat_min_weekly departures a week, in a scan of the last 7
  -- days pauses the route (manual §5, since 21 Oct): the threats as competition() lists them (1b), the one paused longest
  thr as (select distinct on (t.a, t.b) t.a, t.b, t.rival, t.kind, t.added_weekly, t.scan_at, t.until
            from private.competition_threats(p_airline_id, p_as_of) t
           order by t.a, t.b, t.until desc, t.now_weekly desc, t.rival),
  -- the routes and cabins on the ladder: each flying route in economy, and in business where its aircraft have business
  -- seats; any with flights captured in the 7 days or a move recorded this week. Since 26 Oct each in both directions
  rc as (select distinct x.route_id, x.cabin, d.dir
           from (select f.route_id, 'economy'::text as cabin from fq f where f.live
                 union all select bz.route_id, 'business' from biz bz
                 union all select st.route_id, st.cabin from st
                 union all select wk.route_id, wk.cabin from wk) x
           join ro on ro.id = x.route_id
           cross join (values ('out'), ('back')) d (dir)),
  lv as (select rc.route_id, rc.cabin, rc.dir, ro.hub_code as hub, ro.dest_code as dest,
                case rc.dir when 'out' then ro.hub_code else ro.dest_code end as dir_from,
                case rc.dir when 'out' then ro.dest_code else ro.hub_code end as dir_to,
                coalesce(st.n, 0) as n, coalesce(st.sold, 0) as sold, st.fare as fare_week, st.load as load_week,
                lt.fare as latest_fare, lt.day as latest_on, lt.ratios, lt.inf, eb.fare as baseline_fare, eb.day as baseline_on,
                coalesce(eb.source, 'inferred') as default_source, eb.default_on,
                -- a joiner's level is the pair's: the owner's (since 5 Nov)
                case when pm.role = 'joiner' then coalesce(op.level_pct, pm.p_launch) else coalesce(pv.level_pct, v_launch) end as level,
                case when pm.role = 'joiner' then op.id is not null else pv.id is not null end as recorded,
                case when pm.role = 'joiner' then null else wk.id end as plan_id, wk.level_pct as plan_level, wk.ladder_move as plan_move, wk.reason as plan_reason,
                pm.role, pm.p_route, pm.p_airline, pm.p_name, pm.p_hub, pm.p_dest,
                -- the owner's direction that leaves the same airport as this one
                case when (ro.hub_code = pm.p_hub) = (rc.dir = 'out') then 'out' else 'back' end as pair_dir,
                ow.level_pct as p_plan_level, ow.ladder_move as p_plan_move, pa.last_day as p_last_day,
                case when pm.role = 'joiner' then pm.p_launch else v_launch end as l_launch,
                case when pm.role = 'joiner' then pm.p_step else v_step end as l_step,
                case when pm.role = 'joiner' then pm.p_cap else v_cap end as l_cap,
                coalesce(se.applied, false) as applied, se.seen_on, dn.down_on, upr.up_on, ag.first_day, ad.last_day,
                exists (select 1 from contested c where c.a = least(ro.hub_code, ro.dest_code) and c.b = greatest(ro.hub_code, ro.dest_code)) as contested,
                th.rival as rv_name, th.kind as rv_kind, th.added_weekly as rv_added, th.scan_at as rv_on, th.until as rv_until,
                jl.jumped_on, ud.route_id is not null as ul_done, um.route_id is not null as ul_marked, lch.changed_on,
                coalesce(uw.n, 0) as w_n, uw.load as w_load,
                coalesce(uj.n, 0) as j_n, uj.load as j_load,
                coalesce(ujw.n, 0) as jw_n, ujw.load as jw_load
           from rc join ro on ro.id = rc.route_id
           left join thr th on th.a = least(ro.hub_code, ro.dest_code) and th.b = greatest(ro.hub_code, ro.dest_code)
           left join st on st.route_id = rc.route_id and st.cabin = rc.cabin and st.dir = rc.dir
           left join latest lt on lt.route_id = rc.route_id and lt.cabin = rc.cabin and lt.dir = rc.dir
           left join eb on eb.route_id = rc.route_id and eb.cabin = rc.cabin and eb.dir = rc.dir
           left join prev pv on pv.route_id = rc.route_id and pv.cabin = rc.cabin and pv.dir = rc.dir
           left join wk on wk.route_id = rc.route_id and wk.cabin = rc.cabin and wk.dir = rc.dir
           left join seen se on se.id = wk.id
           left join dn on dn.route_id = rc.route_id and dn.cabin = rc.cabin and dn.dir = rc.dir
           left join upr on upr.route_id = rc.route_id and upr.cabin = rc.cabin and upr.dir = rc.dir
           left join age ag on ag.route_id = rc.route_id
           left join added ad on ad.route_id = rc.route_id
           left join jl on jl.route_id = rc.route_id and jl.cabin = rc.cabin and jl.dir = rc.dir
           left join ud on ud.route_id = rc.route_id and ud.cabin = rc.cabin and ud.dir = rc.dir
           left join um on um.route_id = rc.route_id and um.cabin = rc.cabin and um.dir = rc.dir
           left join lch on lch.route_id = rc.route_id and lch.cabin = rc.cabin and lch.dir = rc.dir
           left join uw on uw.route_id = rc.route_id and uw.cabin = rc.cabin and uw.dir = rc.dir
           left join uj on uj.route_id = rc.route_id and uj.cabin = rc.cabin and uj.dir = rc.dir
           left join ujw on ujw.route_id = rc.route_id and ujw.cabin = rc.cabin and ujw.dir = rc.dir
           left join pm on pm.route_id = rc.route_id
           left join oprev op on op.route_id = rc.route_id and op.cabin = rc.cabin and op.dir = rc.dir
           left join owk ow on ow.route_id = rc.route_id and ow.cabin = rc.cabin and ow.dir = rc.dir
           left join padd pa on pa.route_id = rc.route_id),
  mv0 as (select lv.*,
                case when lv.n > 0 then lv.sold * 100.0 / lv.n end as share,
                lv.l_launch + lv.l_cap as cap_pct,
                -- never under launch, nor under the house floor where another player flies the pair
                greatest(lv.l_launch, case when lv.contested then v_floor end) as floor_pct,
                -- a joiner's first flights aren't a new route: they start at the pair's level (since 5 Nov)
                coalesce(lv.role is distinct from 'joiner' and lv.first_day is not null and v_today - lv.first_day < v_new_days, false) as young,
                coalesce(lv.down_on is not null and v_week - lv.down_on < v_hold * 7, false) as held,
                -- the hold after a step up (since 26 Oct): the next Saturday, fare_ladder_up_hold_weeks
                coalesce(lv.up_on is not null and v_week - lv.up_on < v_up_hold * 7, false) as held_up,
                -- a flight added in the last fare_ladder_capacity_hold_days, to a route older than that (manual §5, since 21 Oct);
                -- on a pair the airline owns, by either airline (since 5 Nov)
                greatest(lv.last_day, lv.p_last_day) as added_day,
                coalesce(greatest(lv.last_day, lv.p_last_day) is not null and v_today - greatest(lv.last_day, lv.p_last_day) < v_added_days
                         and lv.first_day is not null and v_today - lv.first_day >= v_added_days, false) as added,
                -- under launch (since 23 Oct): the cabin's state, from the fare plan's rows before this Saturday. launch: at
                -- its launch level and never jumped; holding: its latest jump under fare_under_launch_days old, counted from
                -- the day it took effect; due: the hold is over, still at the jump level, judged on its loads each Saturday
                -- (since 26 Oct); done: it climbed after the jump, or is back at launch (a revert before 26 Oct)
                case when lv.role = 'joiner' then null
                     when lv.jumped_on is null then case when lv.level = v_launch and v_ul_below is not null then 'launch' end
                     when lv.ul_done or lv.level >= v_launch then 'done'
                     when v_today - lv.jumped_on < v_ul_days then 'holding'
                     else 'due' end as ul_state,
                lv.jumped_on + v_ul_days::int as judge_on,
                -- the latest recorded level change (a cabin back at launch after a step down): the window must have none,
                -- so all its flights are at the launch level (spec §2); a new route waits as before (growth_new_route_days)
                lv.changed_on as launch_since,
                -- the jump levels under the cabin's level: the next is the first of them; at the last, none is left
                (select u.l from unnest(v_ul_below) with ordinality as u(l, i) where u.l < lv.level order by u.i limit 1) as next_level
           from lv),
  -- the under-launch kind (spec §2), worked out before this week's plan so a move put on the plan this week keeps it.
  -- Since 26 Oct (spec docs/specs/2026-10-26-under-launch-by-loads.md) a cabin due is judged on the week's loads as any
  -- direction: sold out it steps up and 90–99% sold out it holds (the normal ladder's own kinds); under 90% sold out, with
  -- the minimum departures, it jumps to the next level, or at the last level holds there marked cut or keep? Since 2 Nov
  -- (manual §5) the next jump also needs the cabin under fare_under_launch_load_pct full over its last fare_under_launch_days
  -- since the jump (ujw), as the first jump does; 80% full or more (or no flights in that window) it holds at its level
  -- (ul_full) and is judged again the next Saturday. The cut-or-keep test at the last level is unchanged.
  mv as (select mv0.*,
                case
                  when mv0.ul_state = 'launch' then
                    case when mv0.share >= v_down or mv0.n < v_min or mv0.w_load is null or mv0.w_load >= v_ul_load then null
                         when mv0.launch_since is not null and p_as_of - make_interval(days => v_ul_days::int) < mv0.launch_since::timestamp at time zone 'UTC' then 'ul_since'
                         when mv0.w_n < v_ul_min then 'ul_few'
                         else 'ul_jump' end
                  when mv0.ul_state = 'holding' then 'ul_hold'
                  when mv0.ul_state = 'due' then
                    case when mv0.n < v_min or mv0.share >= v_down then null
                         when mv0.next_level is not null and (mv0.jw_load is null or mv0.jw_load >= v_ul_load) then 'ul_full'
                         when mv0.next_level is not null then 'ul_jump'
                         else 'ul_decide' end
                end as uk
           from mv0),
  -- materialized (since 5 Nov): the steps after it name its kind (k) and the levels many times over, and inlined, each
  -- name repeated the whole chain of expressions beneath it (fin, od, ix and fx made the builder seconds slower on the
  -- copy); worked out once here, the rows and answers are the same
  dc as materialized (select mv.*,
                -- a joiner follows the pair's level and moves (since 5 Nov): never a move of its own
                case when mv.role = 'joiner' then 'follows'
                     when mv.plan_id is not null then 'planned'
                     when mv.young then 'young'
                     when mv.n < v_min then 'few'
                     -- a direction held both ways takes the more recent move's reason (the step down on the same day)
                     when mv.held and not (mv.held_up and mv.up_on > mv.down_on) then 'held'
                     when mv.held_up then 'held_up'
                     when mv.added then 'added'
                     when mv.rv_name is not null then 'rival'
                     -- under launch (since 23 Oct; spec §2): the jump at launch only where the ladder would hold at launch
                     -- (under fare_ladder_down_share sold out); the hold whatever it sells; once due (since 26 Oct) the next
                     -- jump or the cut-or-keep hold under fare_ladder_down_share sold out, else the normal ladder below
                     when mv.uk in ('ul_hold', 'ul_decide', 'ul_full') or (mv.uk = 'ul_jump' and mv.ul_state = 'due') then mv.uk
                     when mv.uk in ('ul_jump', 'ul_few', 'ul_since') and mv.level <= mv.floor_pct then mv.uk
                     -- under launch, once jumped, the ladder only climbs or holds (never a 5-point step down)
                     when mv.level < v_launch and mv.share < v_down then 'ul_climb'
                     when mv.share >= v_up then case when mv.level >= mv.cap_pct then 'capped' else 'up' end
                     when mv.share >= v_down then 'hold'
                     when mv.level <= mv.floor_pct then 'floor'
                     else 'down' end as k
           from mv),
  fin as (select dc.*,
                 -- a jump is a move down (since 23 Oct), so existing readers keep working; ladder_kind says which (a revert
                 -- on the fare plan, recorded before 26 Oct, is a move up)
                 case dc.k when 'planned' then case dc.plan_move when 'jump' then 'down' when 'revert' then 'up' else dc.plan_move end
                           when 'follows' then case dc.p_plan_move when 'jump' then 'down' when 'revert' then 'up' when 'up' then 'up' when 'down' then 'down' else 'hold' end
                           when 'up' then 'up' when 'down' then 'down' when 'ul_jump' then 'down' else 'hold' end as move,
                 case dc.k when 'planned' then dc.plan_move when 'follows' then coalesce(dc.p_plan_move, 'hold')
                           when 'up' then 'up' when 'down' then 'down' when 'ul_jump' then 'jump'
                           else 'hold' end as ladder_kind,
                 case dc.k when 'planned' then dc.plan_level when 'follows' then coalesce(dc.p_plan_level, dc.level)
                           when 'up' then least(dc.level + v_step, dc.cap_pct)
                           when 'down' then greatest(dc.level - v_step, dc.floor_pct)
                           when 'ul_jump' then dc.next_level
                           else dc.level end as new_level,
                 -- a cut-or-keep decision for Gitesh (since 23 Oct; by loads since 26 Oct): due at the last jump level and
                 -- held there this Saturday under fare_ladder_down_share sold out (or that hold put on the fare plan this
                 -- week), or marked so before (a hold recorded after the jump); it stays marked, whatever holds it, until it
                 -- climbs (a step up this Saturday, or on the fare plan)
                 coalesce(dc.ul_state = 'due' and dc.next_level is null
                          and (dc.k = 'ul_decide' or (dc.k = 'planned' and dc.uk = 'ul_decide') or dc.ul_marked)
                          and dc.k <> 'up' and not (dc.k = 'planned' and dc.plan_move is not distinct from 'up'), false) as decide,
                 case when dc.contested and v_floor > v_launch then format('the %s%% floor', trim_scale(v_floor))
                      else format('launch (%s%%)', trim_scale(v_launch)) end as floor_words
            from dc),
  od as (select fin.*,
                 case fin.k
                   when 'planned' then coalesce(fin.plan_reason, 'on the fare plan')
                   when 'young' then format('new route, launched %s', to_char(fin.first_day, 'FMDD Mon'))
                   when 'few' then case when fin.n = 0 then 'no departures captured'
                                        else format('%s departure%s captured, needs %s', fin.n, case when fin.n = 1 then '' else 's' end, trim_scale(v_min)) end
                   when 'held' then format('held after a step down on %s', to_char(fin.down_on, 'FMDD Mon'))
                   when 'held_up' then format('held after a step up on %s', to_char(fin.up_on, 'FMDD Mon'))
                   when 'added' then format('a flight added on %s%s: judged at its new size from %s', to_char(fin.added_day, 'FMDD Mon'),
                                            case when fin.role = 'owner' and fin.p_last_day is not distinct from fin.added_day
                                                      and fin.last_day is distinct from fin.added_day then ' by ' || fin.p_name else '' end,
                                            to_char(fin.added_day + v_added_days::int, 'FMDD Mon'))
                   -- shared pairs (since 5 Nov)
                   when 'follows' then format('follows %s''s ladder on %s–%s', fin.p_name, fin.p_hub, fin.p_dest)
                                       || case when fin.p_plan_level is not null
                                               then format(': on its fare plan this week at %s%%', trim_scale(fin.p_plan_level)) else '' end
                   when 'rival' then format('rival %s %s here on %s: paused until %s', fin.rv_name,
                                            case when fin.rv_kind = 'started' then 'started' else format('added %s a week', fin.rv_added) end,
                                            to_char(fin.rv_on at time zone 'UTC', 'FMDD Mon'), to_char(fin.rv_until at time zone 'UTC', 'FMDD Mon'))
                   when 'up' then format('sold out %s of %s', fin.sold, fin.n)
                                  || case when fin.level + v_step >= fin.cap_pct then format(', up to the %s%% cap', trim_scale(fin.cap_pct)) else '' end
                   when 'capped' then format('sold out %s of %s, capped at %s%%', fin.sold, fin.n, trim_scale(fin.cap_pct))
                   when 'hold' then format('sold out %s of %s', fin.sold, fin.n)
                   when 'down' then format('sold out %s of %s', fin.sold, fin.n)
                                    || case when fin.level - v_step <= fin.floor_pct then ', down to ' || fin.floor_words else '' end
                   -- under launch (since 23 Oct; spec §2)
                   when 'ul_jump' then case when fin.ul_state = 'due'
                     then format('at %s%% since %s: sold out %s of %s: to %s%% for %s', trim_scale(fin.level), to_char(fin.jumped_on, 'FMDD Mon'),
                                 fin.sold, fin.n, trim_scale(fin.next_level), v_ul_span)
                     else format('%s%% full over %s days at launch: to %s%% for %s', round(fin.w_load), trim_scale(v_ul_days), trim_scale(fin.next_level), v_ul_span) end
                   when 'ul_full' then case when fin.jw_load is null
                     then format('at %s%% since %s: sold out %s of %s, no flights in the last %s days: holds at %s%%', trim_scale(fin.level),
                                 to_char(fin.jumped_on, 'FMDD Mon'), fin.sold, fin.n, trim_scale(v_ul_days), trim_scale(fin.level))
                     else format('at %s%% since %s: sold out %s of %s but %s%% full over %s days: holds at %s%%, judged again next Saturday', trim_scale(fin.level),
                                 to_char(fin.jumped_on, 'FMDD Mon'), fin.sold, fin.n, round(fin.jw_load), trim_scale(v_ul_days), trim_scale(fin.level)) end
                   when 'ul_hold' then format('at %s%% since %s: judged on %s', trim_scale(fin.level), to_char(fin.jumped_on, 'FMDD Mon'), to_char(fin.judge_on, 'FMDD Mon'))
                   when 'ul_decide' then format('at %s%% since %s: sold out %s of %s: holds at %s%%; cut or keep? (Saturday review)',
                                                trim_scale(fin.level), to_char(fin.jumped_on, 'FMDD Mon'), fin.sold, fin.n, trim_scale(fin.level))
                   when 'ul_few' then format('sold out %s of %s, at %s: %s flight%s in %s days, needs %s to jump', fin.sold, fin.n, fin.floor_words, fin.w_n,
                                             case when fin.w_n = 1 then '' else 's' end, trim_scale(v_ul_days), trim_scale(v_ul_min))
                   when 'ul_since' then format('sold out %s of %s, at %s since %s: may jump from %s', fin.sold, fin.n, fin.floor_words,
                                               to_char(fin.launch_since, 'FMDD Mon'), to_char(fin.launch_since + v_ul_days::int, 'FMDD Mon'))
                   when 'ul_climb' then 'under launch: climbs or holds only'
                   else format('sold out %s of %s, at %s', fin.sold, fin.n, fin.floor_words) end as reason,
                 -- the level the game should show: this week's, once the captures see it
                 -- a joiner's: the pair's, this week's move as soon as it is on the owner's fare plan (since 5 Nov), so its
                 -- set-back goes with the owner's change
                 case when fin.k = 'follows' then fin.new_level when fin.plan_id is not null and fin.applied then fin.new_level else fin.level end as expect
            from fin),
  -- the fare index: each flight of the latest captured day as a % of the default price (against the market's default, or
  -- the inferred baseline times the launch level: latest's ratios); the day's average to 0.1, and the flight furthest from
  -- the level the game should show. inferred_index: the same day read the old way (against the inferred baseline), kept
  -- to compare (spec §4)
  ix as (select od.*,
                (select round(avg(r), 1) from unnest(od.ratios) r) as fare_index,
                (select r from unnest(od.ratios) r order by abs(r - od.expect) desc limit 1) as worst,
                (select round(avg(r), 1) from unnest(od.inf) r) as inferred_index
           from od),
  fx as (select ix.*,
                case when ix.worst is not null then abs(ix.worst - ix.expect) <= 1 end as matches,
                -- set back (manual §5, since 21 Oct): off its level, not on the fare plan this week, not new, and captured
                -- since its newest rotation launched
                -- since; a joiner's direction whatever its age, never on its own fare plan (since 5 Nov)
                coalesce(ix.worst is not null and abs(ix.worst - ix.expect) > 1 and (ix.k = 'follows' or (ix.plan_id is null and not ix.young))
                         and (ix.last_day is null or ix.latest_on > ix.last_day), false) as fix
           from ix)
  select coalesce(jsonb_agg(jsonb_build_object(
           -- since 26 Oct a row per direction: out from the route's hub, back to it, with its airports that way round
           'route_id', o.route_id, 'hub', o.hub, 'dest', o.dest, 'direction', o.dir, 'from', o.dir_from, 'to', o.dir_to, 'cabin', o.cabin,
           'departures', o.n, 'sold_out', o.sold, 'sold_out_share', round(o.share, 1), 'load', round(o.load_week, 1), 'average_fare', round(o.fare_week, 2),
           'baseline_fare', round(o.baseline_fare, 2), 'baseline_on', o.baseline_on, 'latest_fare', round(o.latest_fare, 2), 'latest_on', o.latest_on,
           'fare_index', o.fare_index, 'index_matches', o.matches,
           -- since 4 Nov: market (baseline_fare is the game's default price, read on default_on) or inferred (no market read
           -- of that direction yet: the first captured fare as before); the inferred index beside it, to compare
           'default_source', o.default_source, 'default_on', o.default_on, 'inferred_index', o.inferred_index,
           'level', trim_scale(o.level), 'recorded', o.recorded, 'steps', trim_scale(round((o.level - o.l_launch) / o.l_step, 1)),
           'move', o.move, 'new_level', trim_scale(o.new_level), 'new_steps', trim_scale(round((o.new_level - o.l_launch) / o.l_step, 1)),
           'change_pct', case when o.level > 0 then trim_scale(round((o.new_level / o.level - 1) * 100, 1)) end,
           'reason', o.reason, 'contested', o.contested, 'floor', trim_scale(o.floor_pct), 'cap', trim_scale(o.cap_pct), 'new_route', o.young,
           'planned', o.plan_id is not null, 'plan_id', o.plan_id, 'applied', o.applied, 'seen_on', o.seen_on,
           -- what Put on the fare plan writes: every level that changes (jumps included), a hold that follows a step down,
           -- and since 26 Oct the first cut-or-keep hold under launch (so the mark stays)
           'to_plan', o.k <> 'follows' and o.plan_id is null and ((o.move in ('up', 'down') and o.new_level <> o.level) or o.k = 'held' or (o.k = 'ul_decide' and not o.ul_marked)),
           -- under launch (since 23 Oct): what Put on the fare plan writes as ladder_move, the cabin's state with its
           -- figures, and whether it is a cut-or-keep decision for Gitesh
           'ladder_kind', o.ladder_kind,
           'under_launch', case when o.ul_state is not null then jsonb_strip_nulls(jsonb_build_object(
             'state', o.ul_state,
             'window_load', round(case when o.ul_state = 'launch' then o.w_load else o.j_load end, 1),
             'window_flights', case when o.ul_state = 'launch' then o.w_n else o.j_n end,
             'jumped_on', o.jumped_on, 'judge_on', o.judge_on,
             -- since 2 Nov: the window a cabin due is judged on (the last fare_under_launch_days since the jump)
             'judged_load', case when o.ul_state = 'due' then round(o.jw_load, 1) end,
             'judged_flights', case when o.ul_state = 'due' then o.jw_n end)) end,
           'decide', o.decide,
           -- a change that sets it back to its level (manual §5, since 21 Oct)
           'fix', o.fix,
           'fix_reason', case when o.fix then format('captured fare at %s%%, %slevel %s%%', trim_scale(round(o.worst, 1)),
                                                    case when o.k = 'follows' then 'the pair''s ' else '' end, trim_scale(o.expect)) end,
           -- shared pairs (since 5 Nov; spec docs/specs/2026-11-05-shared-pairs.md §2): on a joiner's row the pair's owner,
           -- whose level and move it shows (its direction, the one leaving the same airport); on an owner's row the joiner,
           -- whose flights the row's departures, sold-out share and load count with the owner's
           'follows', case when o.role = 'joiner' then jsonb_build_object('airline_id', o.p_airline, 'airline', o.p_name, 'route_id', o.p_route,
                                                                          'hub', o.p_hub, 'dest', o.p_dest, 'direction', o.pair_dir) end,
           'shared_with', case when o.role = 'owner' then jsonb_build_object('airline_id', o.p_airline, 'airline', o.p_name, 'route_id', o.p_route) end)
           order by o.hub, o.dest, o.dir = 'back', o.cabin desc), '[]'::jsonb)
    into v_rows from fx o;

  -- the game's Ticket price adjustments, route by route only (manual §5, since 21 Oct: never a whole base, so a route
  -- under 7 days old is never touched). Each sets the level with the baseline default price. Since 26 Oct each direction
  -- has its own level, so each direction is an action of its own (From A to B, From B to A). First the set-back changes
  -- (fix), then the week's moves, each in the rows' order (hub, dest, out before back): for each direction, when both
  -- cabins go to the same level, one action with both classes ticked; otherwise one for each cabin, economy first. A
  -- direction whose levels don't change gets no action.
  for v_r in select x.fix, x.hub, x.dest, x.dir_from, x.dir_to,
                    jsonb_agg(jsonb_build_object('cabin', x.cabin, 'level', x.level, 'reason', x.reason) order by x.cabin = 'business') as moves
               from (select true as fix, e ->> 'route_id' as route_id, e ->> 'hub' as hub, e ->> 'dest' as dest, e ->> 'direction' as dir,
                            e ->> 'from' as dir_from, e ->> 'to' as dir_to, e ->> 'cabin' as cabin,
                            -- a joiner's set-back goes to the pair's level, this week's once on the owner's plan (since 5 Nov)
                            (case when e ->> 'follows' is not null then e ->> 'new_level' else e ->> 'level' end)::numeric as level,
                            e ->> 'fix_reason' as reason
                       from jsonb_array_elements(v_rows) e
                      where (e ->> 'fix')::boolean
                     union all
                     select false, e ->> 'route_id', e ->> 'hub', e ->> 'dest', e ->> 'direction', e ->> 'from', e ->> 'to', e ->> 'cabin',
                            (e ->> 'new_level')::numeric, null
                       from jsonb_array_elements(v_rows) e
                      where (e ->> 'new_level')::numeric <> (e ->> 'level')::numeric and e ->> 'follows' is null) x
              group by x.fix, x.route_id, x.hub, x.dest, x.dir, x.dir_from, x.dir_to
              order by x.fix desc, x.hub, x.dest, x.dir = 'back' loop
    if jsonb_array_length(v_r.moves) = 2 and (v_r.moves #>> '{0,level}')::numeric = (v_r.moves #>> '{1,level}')::numeric then
      v_sets := jsonb_build_array(jsonb_build_object(
        'classes', jsonb_build_array('economy', 'business'), 'level', v_r.moves #> '{0,level}',
        'reason', case when v_r.fix then format('economy: %s; business: %s', v_r.moves #>> '{0,reason}', v_r.moves #>> '{1,reason}') end));
    else
      select jsonb_agg(jsonb_build_object('classes', jsonb_build_array(m ->> 'cabin'), 'level', m -> 'level', 'reason', m -> 'reason') order by i) into v_sets
        from jsonb_array_elements(v_r.moves) with ordinality as t(m, i);
    end if;
    for v_change in select x from jsonb_array_elements(v_sets) x loop
      v_lv := (v_change ->> 'level')::numeric;
      select string_agg(c, ' and ' order by i) into v_words from jsonb_array_elements_text(v_change -> 'classes') with ordinality as t(c, i);
      v_n := v_n + 1;
      v_actions := v_actions || jsonb_build_object(
        'n', v_n, 'route', v_r.hub || '–' || v_r.dest, 'classes', v_change -> 'classes', 'from', v_r.dir_from, 'to', v_r.dir_to,
        'level', trim_scale(v_lv), 'sign', case when v_lv >= 100 then '+' else '-' end, 'pct', trim_scale(abs(v_lv - 100)),
        'baseline', 'default price', 'fix', v_r.fix, 'reason', v_change ->> 'reason',
        'text', format('From %s to %s: %s%s%% of the default price, %s', v_r.dir_from, v_r.dir_to,
                       case when v_lv >= 100 then '+' else '−' end, trim_scale(abs(v_lv - 100)), v_words));
    end loop;
  end loop;

  return jsonb_build_object(
    'airline_id', p_airline_id, 'as_of', private.fig_ts(p_as_of), 'week_of', v_week,
    'from', private.fig_ts(p_as_of - interval '7 days'), 'to', private.fig_ts(p_as_of),
    'settings', jsonb_build_object('step_pts', v_step, 'up_share', v_up, 'down_share', v_down, 'min_departures', v_min,
                                   'hold_weeks', v_hold, 'up_hold_weeks', v_up_hold, 'cap_pts', v_cap, 'launch_pct', v_launch, 'cap_pct', v_launch + v_cap,
                                   'floor_pct', v_floor, 'new_route_days', v_new_days, 'capacity_hold_days', v_added_days,
                                   'baseline_day', v_base_day,
                                   'under_launch', jsonb_build_object('load_pct', v_ul_load, 'levels', to_jsonb(v_ul_levels), 'days', v_ul_days,
                                                                      'min_flights', v_ul_min)),
    'scan', case when v_scan is null then null else jsonb_build_object('id', v_scan, 'taken_at', private.fig_ts(v_scan_at)) end,
    'moves', jsonb_build_object(
      'up', (select count(*) from jsonb_array_elements(v_rows) e where e ->> 'move' = 'up' and e ->> 'follows' is null),
      'hold', (select count(*) from jsonb_array_elements(v_rows) e where e ->> 'move' = 'hold' and e ->> 'follows' is null),
      'down', (select count(*) from jsonb_array_elements(v_rows) e where e ->> 'move' = 'down' and e ->> 'follows' is null),
      'jumps', (select count(*) from jsonb_array_elements(v_rows) e where e ->> 'ladder_kind' = 'jump'),
      'decisions', (select count(*) from jsonb_array_elements(v_rows) e where (e ->> 'decide')::boolean)),
    'to_plan', (select count(*) from jsonb_array_elements(v_rows) e where (e ->> 'to_plan')::boolean),
    'planned', (select count(*) from jsonb_array_elements(v_rows) e where (e ->> 'planned')::boolean),
    -- since 5 Nov: a joiner's directions, which follow the pair's owner (not counted in the moves)
    'follows', (select count(*) from jsonb_array_elements(v_rows) e where e ->> 'follows' is not null),
    -- since 26 Oct the directions set back (a route and direction each)
    'off_level', (select count(distinct (e ->> 'route_id') || ' ' || (e ->> 'direction')) from jsonb_array_elements(v_rows) e where (e ->> 'fix')::boolean),
    'routes', v_rows, 'actions', v_actions,
    'notes', jsonb_build_array(
      'Since 4 Nov the fare index measures each flight of the latest captured day against the game''s default price, read each week from the Market Analysis page (default_source market); where the market pages haven''t read a direction yet (default_source inferred), it compares each flight with its direction''s fare on 21 Oct 2026, when every route was at its launch level (or its first captured fare, for a route launched later), times the launch level, as before. Since 26 Oct each direction has its own level, judged on its own flights: a direction more than 1 point off its level gets a change that sets it back, first in the list, unless it''s on the fare plan this week, its route is new, or it isn''t captured since its route''s newest flight launched. Since 5 Nov a shared pair (two of our airlines on one base-to-base pair, manual §2) has one ladder, the owner''s: its rows count the joiner''s flights that way with its own (departures, sold-out share, load), with its step, cap and launch level, and a flight added by either airline holds it; its fare index and set-backs stay its own flights. A joiner''s rows show the pair''s level and this week''s move on the owner''s fare plan (follows), never a move of their own, and list a set-back to the pair''s level for any direction off it.'));
end
$function$

;

-- ============================================================ 6. descriptions
do $describe$
declare x record; d text;
begin
  for x in select * from (values
      ('private.fig_fare_ladder(bigint, timestamptz)', 'Shared pairs (since 5 Nov',
       ' Shared pairs (since 5 Nov, spec docs/specs/2026-11-05-shared-pairs.md §2): on a pair the airline owns with a joiner (routes.shares_route_id), each direction and cabin''s departures, sold-out share and loads (the week''s, and under launch the windows'') count the joiner''s captured flights that way too, matched by airports, and a rotation added on either route holds the pair; the fare index, the inferred baseline and the set-backs stay the airline''s own flights. On a joiner''s route each row follows the owner''s fare plan rows (k follows: the pair''s level, this week''s move once on the owner''s plan, the owner''s launch, step and cap), never a move of its own and never to_plan, and lists a set-back to the pair''s level (this week''s once on the owner''s plan) for a direction off it, whatever the route''s age. The game''s default price on a shared pair is the latest read under either airline.'),
      ('public.fare_ladder(bigint, timestamptz)', 'Since 5 Nov (spec docs/specs/2026-11-05-shared-pairs.md §2) a shared pair',
       ' Since 5 Nov (spec docs/specs/2026-11-05-shared-pairs.md §2) a shared pair has one ladder, the owner''s: an owner''s rows count the joiner''s flights with its own (departures, sold_out, sold_out_share, load) and carry shared_with (the joiner''s airline_id, airline and route_id), and a flight added by either airline holds the pair; a joiner''s rows carry follows (the owner''s airline_id, airline, route_id, hub, dest and the matching direction), show the pair''s level and this week''s move on the owner''s fare plan (move, new_level), are never to_plan, list only set-backs to the pair''s level (fix, "the pair''s level" in fix_reason) and aren''t counted in moves; follows counts them. The review presses Put on the fare plan for the owner before the joiner.')
    ) v(f, mark, more) loop
    d := obj_description(x.f::regprocedure, 'pg_proc');
    if position(x.mark in coalesce(d, '')) = 0 then
      execute format('comment on function %s is %L', x.f, coalesce(d, '') || x.more);
    end if;
  end loop;
end
$describe$;

select set_config('equinox.actor', '', true), set_config('equinox.actor_detail', '', true);

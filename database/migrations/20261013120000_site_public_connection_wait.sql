-- site_public() gives the longest wait for a connection (decision #19, build pull request 4, "the scripts and the
-- website onto the library and the figures"). Design: docs/design/2026-10-12-planner-app.md §7 ("For the website").
-- Spec: docs/specs/2026-10-13-callers.md §3.
--
-- Changes one function; adds and removes nothing else, so there is no separate file for Gitesh:
--   public.site_public(): content gains connection_max_wait_h, the world's setting (hours; 8 on 13 Oct, manual §4). The
--     website's trip search now uses the planning library's connection test (web/assets/rules.js): a transfer counts
--     from the airport's minimum connection time (content.mct, 90 minutes where unknown) to this many hours (it was 10
--     hours, typed into the website). Left out when the setting is missing or isn't a number; the website then uses 8.
--     Every other part of the answer is unchanged; it grows by about 30 bytes.

select set_config('equinox.actor', 'migration', true),
       set_config('equinox.actor_detail', '20261013120000_site_public_connection_wait', true);

-- ============================================================ site_public()
-- As 20261010220000_website_and_scripts.sql left it, with the one new key in content.
create or replace function public.site_public()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
    -- site_content's keys (photos, logos ...; markets is the investors'), with mct from world_airports, and the longest
    -- wait for a connection from settings (connection_max_wait_h, hours, manual §4), for the trip search (#19)
    'content', coalesce((select jsonb_object_agg(c.key, c.value) from public.site_content c where c.key not in ('markets', 'mct')), '{}'::jsonb)
               || coalesce((select jsonb_build_object('mct', jsonb_object_agg(wa.airport_code, wa.mct_min))
                              from w join public.world_airports wa on wa.world_id = w.id
                             where wa.mct_min is not null
                            having count(*) > 0), '{}'::jsonb)
               || coalesce((select jsonb_build_object('connection_max_wait_h', (s.value #>> '{}')::numeric)
                              from w join public.settings s on s.world_id = w.id
                             where s.airline_id is null and s.key = 'connection_max_wait_h'
                               and (s.value #>> '{}') ~ '^\s*[0-9]+(\.[0-9]+)?\s*$'), '{}'::jsonb)
  );
$function$;

revoke all on function public.site_public() from public;
grant execute on function public.site_public() to anon, authenticated;

comment on function public.site_public() is 'Everything the public website shows, in one call: hubs and focus cities an airline flies from, aircraft flying, the week''s frequencies (local times), signed interlines, posts, the reports list, site_content (photos, logos), the minimum connection times (content.mct) and the longest wait for a connection (content.connection_max_wait_h, hours, from settings; the trip search''s window with the planning library, #19), built from the tables (#13, pull request 8), plus our airlines (names, codes, colours, the website''s text, display order) from airlines. Same answer as before #13, apart from airlines, content.connection_max_wait_h and updated_at (when the planner''s data last changed). No bank or transfer times, cabin layouts or aircraft on order (6 Oct). Anyone may call it; runs as owner.';

select set_config('equinox.actor', '', true), set_config('equinox.actor_detail', '', true);

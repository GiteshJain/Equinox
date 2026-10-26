-- The cabin by distance (manual §5, since 26 Oct; brief docs/briefs/2026-10-26-cabin-layout-by-distance.md): each route
-- is in a distance range (Leisure under cabin_leisure_max_km, Leisure Plus to under cabin_leisure_plus_max_km, Comfort
-- beyond), and the range taking more than cabin_route_share_pct of the aircraft's block time decides; with no range
-- over it, the layout with the most seats (Gitesh, Building chat: "65% rule still applies for aircrafts which fly
-- multiple ranges"). Distance alone decides: markets.layout and routes.cabin_choice no longer override it. The rule
-- itself is the planning library's card.cabinFor; this file holds its two new settings (written on live directly on
-- 26 Oct, so a copy from before has them too) and the descriptions of all three. Values already set are kept.
select set_config('equinox.actor', 'claude', true), set_config('equinox.actor_detail', 'building: cabin by distance', true);

insert into public.settings (world_id, airline_id, key, value, unit, description, since, reason)
select w.id, null, x.key, x.value, 'km', x.description, date '2026-10-26',
       'Gitesh, 26 Oct (brief 2026-10-26-cabin-layout-by-distance.md): the layouts trade seat comfort for seats, a question of flight length; demand is met by the fare ladder'
  from public.worlds w
 cross join (values
   ('cabin_leisure_max_km', '3500'::jsonb,
    'The cabin by distance (manual §5): a route under this many km is in the Leisure range. The range taking more than cabin_route_share_pct of an aircraft''s block time decides its layout (the planning library''s card.cabinFor)'),
   ('cabin_leisure_plus_max_km', '6500'::jsonb,
    'The cabin by distance (manual §5): a route from cabin_leisure_max_km to under this many km is in the Leisure Plus range, from it on in the Comfort range. The range taking more than cabin_route_share_pct of an aircraft''s block time decides its layout (the planning library''s card.cabinFor)')
 ) as x(key, value, description)
on conflict on constraint settings_world_airline_key_key
do update set description = excluded.description, unit = excluded.unit, reason = coalesce(public.settings.reason, excluded.reason),
              since = coalesce(public.settings.since, excluded.since);

update public.settings set description =
  'The cabin by distance (manual §5, since 26 Oct): the distance range (cabin_leisure_max_km, cabin_leisure_plus_max_km) taking more than this share of the aircraft''s block time decides its layout; with no range over it, the layout with the most seats. Ryanair flies Standard only. The plan card suggests its cabin by it (the planning library''s card.cabinFor)'
 where key = 'cabin_route_share_pct' and airline_id is null;

comment on column public.markets.layout is 'Since 26 Oct no longer used by the cabin rule (manual §5: the cabin by distance). Was: the cabin layout the market calls for (Standard, Leisure, Leisure Plus or Comfort), taken by a plan card where one route of the market flew more than cabin_route_share_pct of the aircraft''s block time. Kept as history; changed in Reference → Markets';
comment on column public.routes.cabin_choice is 'Since 26 Oct no longer used by the cabin rule (manual §5: distance alone decides). Was: the route''s own cabin layout, which won over its market''s. Kept as history';

create table if not exists public.planner_meta (key text primary key, value jsonb not null, updated_at timestamptz not null default now());
alter table public.planner_meta enable row level security;
drop policy if exists "planner staff read meta" on public.planner_meta;
create policy "planner staff read meta" on public.planner_meta for select to authenticated using (public.is_planner_user());
insert into public.planner_meta(key, value) values ('growthRules', $J${
  "hubsFirst": {"decided":"2026-10-05","hubTarget":750,"metric":"weekly departures by the airline at its main hub",
    "mainHubs":{"Pan American":"JFK","Kingfisher":"DEL","Virgin Atlantic":"LGW","China Eastern":"PVG","Malaysia Airlines":"KUL"},
    "contested":{"airportRivalWeekly":250,"routeRivalPerDay":2,"judgedOn":"the routes the new hub would open with"},
    "exempt":["Ryanair"],
    "contestedNow":["BOM (Gulf routes)","MAN (Amsterdam)","PKX (Chengdu)","DFW if opening with ORD, ATL or PHX","SFO and SEA (rival over 250 a week)"],
    "onHold":["Pan Am DFW","Pan Am LAX","Kingfisher focus cities HYD, BLR, MAA, CCU"]},
  "freedomRoutes": {"noted":"2026-10-05","maxPerAirline":30,
    "definition":"routes with neither end in the airline's home country (5th freedom: between two foreign countries; 8th freedom: within one foreign country)",
    "home":{"Pan American":"US","Kingfisher":"IN","Virgin Atlantic":"GB","China Eastern":"CN","Malaysia Airlines":"MY"},
    "ryanairUnrestricted":"EU-27, Switzerland, Norway and the UK; only routes leaving that area count",
    "countOn":{"2026-10-05":{"Pan American":0,"Kingfisher":0,"Virgin Atlantic":0,"China Eastern":0,"Malaysia Airlines":0,"Ryanair":0}}}
}$J$::jsonb)
on conflict (key) do update set value = excluded.value, updated_at = now();;

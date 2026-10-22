-- Stars come from the game's passenger demand (22 Oct 2026; manual §3, "Size by city stars"; Gitesh, review chat).
-- The review chat read every airport on our lists from its page in Gander and wrote the stars as each route's
-- stars_override (9–10 five stars, 7–8 four, 5–6 three, 3–4 two, 0–2 one), keeping the research's rating in stars.
-- This only describes the column so; no data changes.
select set_config('equinox.actor', 'migration', true),
       set_config('equinox.actor_detail', '20261022080000_stars_description', true);

comment on column public.routes.stars_override is
  'The game''s passenger demand as stars (manual §3, since 22 Oct), or typed in the planner; null = the research value';

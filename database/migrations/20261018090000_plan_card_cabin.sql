-- A plan card carries its cabin (18 Oct; spec docs/specs/2026-10-18-plan-card-cabin.md). The cabin is chosen when an
-- aircraft arrives and its routes are planned (manual §3: an order is just the aircraft), but plan cards had nowhere to
-- keep it: filing gave the aircraft its order's cabin (none, since orders carry none) and logged the first fit at the
-- airline's default cabin for the type, so the 16 aircraft filed 16-18 Oct had no cabin and their fits were logged at the
-- wrong price. Filing now takes the card's cabin, else the order's, else none (and says so).
select set_config('equinox.actor', 'claude', true), set_config('equinox.actor_detail', 'building: plan card cabin', true);

alter table public.plan_cards add column config_id bigint;
alter table public.plan_cards add constraint plan_cards_config_fkey foreign key (config_id, world_id) references public.cabin_configs (id, world_id);
comment on column public.plan_cards.config_id is
  'The cabin the aircraft is fitted with, chosen with its routes; filing gives the aircraft this cabin and logs its first fit at its price (null = not chosen yet)';

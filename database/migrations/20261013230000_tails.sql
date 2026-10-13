-- The new planner's Tails screen and filing (decision #18, build pull request 7). Spec: docs/specs/2026-10-13-tails.md
-- ("the order cabin and its cost come from the database's one home for it (private.fig_order_cabin, design §16): give
-- the screen a staff function for it rather than repeating the old DEFAULT_CABIN in the screen"; "every planning figure
-- from the library; add only what's missing").
--
-- Adds one function and one setting; changes and takes away nothing:
--   public.order_cabin(p_airline_id, p_type_id): the cabin layout an order of that type comes with for that airline
--     (private.fig_order_cabin(), the old planner's DEFAULT_CABIN), with its code, cabin and cost, or null when the type
--     has no such layout. Filing an aircraft logs its first cabin fit with it when the order names no cabin of its own
--     (the old filePlan and cabinCostM). Staff only, read only (called with GET, so a preview reads it too).
--   settings.aircraft_block_target_h (10, every world): the old Tails lists an aircraft flying fewer block hours a day
--     than this among its issues (tailIssues, "under the 10 h target"). A flag on the screen, not a floor (manual §4).
--     The planning library reads it through rules_input(), which carries every setting.

select set_config('equinox.actor', 'migration', true),
       set_config('equinox.actor_detail', '20261013230000_tails', true);

create or replace function public.order_cabin(p_airline_id bigint, p_type_id bigint)
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to ''
as $function$
declare v_id bigint;
begin
  if not private.caller_is_staff() then raise exception 'only planner staff can read the planner' using errcode = '42501'; end if;
  v_id := private.fig_order_cabin(p_airline_id, p_type_id);
  return (select jsonb_build_object('id', c.id, 'code', c.code, 'cabin', c.cabin, 'cost', c.cost, 'aircraft_type_id', c.aircraft_type_id)
            from public.cabin_configs c where c.id = v_id);
end
$function$;

revoke all on function public.order_cabin(bigint, bigint) from public, anon, authenticated, service_role;
grant execute on function public.order_cabin(bigint, bigint) to authenticated;

comment on function public.order_cabin(bigint, bigint) is 'The cabin layout an order of a type comes with for an airline (decision #18, build pull request 7; private.fig_order_cabin(), the old planner''s DEFAULT_CABIN): {id, code, cabin, cost, aircraft_type_id}, or null when the type has no such layout. Filing an aircraft into the planner logs its first cabin fit at this cost when the order names no cabin of its own (the old filePlan and cabinCostM). Staff only; runs as owner and checks the caller itself.';

insert into public.settings (world_id, airline_id, key, value, unit, description, since, reason)
select w.id, null, 'aircraft_block_target_h', '10'::jsonb, 'block hours a day',
       'Tails lists an aircraft flying fewer block hours a day than this among its issues (the old planner''s tailIssues). A flag on the screen, not a floor: manual §4 sets none',
       date '2026-10-13', 'The old planner''s 10 h target, given a home of its own (#19)'
  from public.worlds w
on conflict on constraint settings_world_airline_key_key do nothing;

select set_config('equinox.actor', '', true), set_config('equinox.actor_detail', '', true);

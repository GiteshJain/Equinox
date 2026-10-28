-- The planning target for connections (27 Oct 2026; manual §4, "Maximise connections at both ends"; spec
-- docs/specs/2026-10-27-planning-connection-target.md, brief docs/briefs/2026-10-27-connection-waits.md, option B,
-- planning only).
--
-- Why: only about a third of our flights sit in their hub's banks, and 58% of our 5,447 connections wait more than
-- 4 hours. The optimiser scored every connection up to 8 hours alike, so nothing pulled flights into the banks. A flight
-- in its bank connects in the minimum connection time to about two hours more, so 4 hours means "in a bank, or close".
--
-- Adds one settings row and changes, drops and renames nothing, so it can be applied from the chat:
--   settings.plan_connection_target_h: 4 hours, world-level in every world (airline null), described. It reaches the
--   planning library through rules_input(), which carries every world setting as it is (no function changes). The
--   optimiser scores first the connections from the minimum connection time to it, and the card check reports how many
--   fall within it; nothing else reads it. connection_max_wait_h stays 8 for everything else.

select set_config('equinox.actor', 'claude', true), set_config('equinox.actor_detail', 'building: planning connection target', true);

insert into public.settings (world_id, airline_id, key, value, unit, description, since, reason)
select w.id, null, 'plan_connection_target_h', '4'::jsonb, 'hours',
       'The planning target for connections (manual §4): plans and retimes aim for connections within this long of the arrival, from the airport''s minimum connection time. The optimiser scores first the connections within it, then all of them to connection_max_wait_h, then maintenance; the plan card''s check reports how many fall within it (count and share), for the card and each leg, never as a problem. Nothing else reads it: a connection still counts up to connection_max_wait_h everywhere (Routes, hub readiness, the banks, rivals'' connections, the website''s trip search, the connection audit, the weekly report)',
       date '2026-10-27', 'Gitesh, 27 Oct: option B of the brief docs/briefs/2026-10-27-connection-waits.md, planning only: 58% of our connections waited over 4 hours, and the optimiser scored every connection up to 8 hours alike'
  from public.worlds w
on conflict on constraint settings_world_airline_key_key do nothing;

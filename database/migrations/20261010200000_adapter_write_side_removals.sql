-- GITESH RUNS THIS FILE HIMSELF in Supabase's SQL editor (operating manual §1), BEFORE the Building chat applies
-- 20261010210000_adapter_write_side.sql: it removes rules, so it isn't applied from a chat. Paste the lines below and
-- press Run; the Building chat then records it and checks it.
--
-- Decision #13, build pull request 5 (the Building chat's call, 10 Oct): values the old planner writes in ordinary use,
-- which these rules refused, so every side-by-side comparison after one would fail. Nothing is dropped but the rules,
-- and no row changes.
--   1. An interline record may have no status: the planner's "not contacted", with a partner, date or note typed.
--   2. A cabin layout's cabin is stored as typed, not only Standard, Leisure, Leisure Plus or Comfort.
--   3-5. Types, cabin layouts and services: two rows may share a blank code, as when "Add config" is clicked twice (the
--      planner's placeholders "New type", "NEW" and "S5", or an empty one). The main migration puts back the same rule
--      for every other code (a unique index that leaves the blank codes out).
alter table public.interline_agreements alter column status drop not null;
alter table public.cabin_configs drop constraint cabin_configs_cabin_check;
alter table public.aircraft_types drop constraint aircraft_types_world_name_key;
alter table public.cabin_configs drop constraint cabin_configs_world_code_key;
alter table public.service_profiles drop constraint service_profiles_world_code_key;
